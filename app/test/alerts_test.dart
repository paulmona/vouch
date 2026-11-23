import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vouch/alerts/alerts.dart';
import 'package:vouch/app.dart';
import 'package:vouch/keys/device_key.dart';
import 'package:vouch/pairing/device_session.dart';
import 'package:vouch/pairing/paired_device.dart';
import 'package:vouch/push/push_service.dart';

import 'helpers/fake_keys.dart';

/// Alerts: listed from the server, marked on Home until opened, and opened
/// from a notification, with or without push.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final paired = PairedDevice(
    deviceId: 'dev_0123456789',
    serverUrl: Uri.parse('https://vouch.example.com'),
    serverName: 'home-server',
    requireUserAuth: true,
    userAuthBound: 'attested',
    pairedAt: DateTime.utc(2026, 11, 5),
  );

  final leak = {
    'alert_id': 'alt_0123456789',
    'severity': 'critical',
    'title': 'TEST canary',
    'body': 'A test of the leak check. Nothing leaked.',
    'created_at': '2026-11-16T19:00:00Z',
  };

  http.Response json(Object body) => http.Response(
    jsonEncode(body),
    200,
    headers: {'content-type': 'application/json'},
  );

  /// A server holding [alerts]; [listed] false is a server from before
  /// `GET /v1/alerts` (404), which still serves one alert by id.
  Future<http.Response> Function(http.Request) server(
    List<Map<String, Object?>> alerts, {
    bool listed = true,
  }) => (r) async {
    if (r.url.path == '/v1/requests/pending') {
      return json({'requests': <Object>[]});
    }
    if (r.url.path == '/v1/alerts' && listed) return json({'alerts': alerts});
    if (r.url.path.startsWith('/v1/alerts/')) {
      final id = r.url.pathSegments.last;
      for (final a in alerts) {
        if (a['alert_id'] == id) return json(a);
      }
    }
    return http.Response('', 404);
  };

  Future<void> open(
    WidgetTester tester,
    Future<http.Response> Function(http.Request) handler, {
    Map<String, Object> prefs = const {},
  }) async {
    SharedPreferences.setMockInitialValues({
      PairedDeviceStore.key: jsonEncode(paired.toJson()),
      ...prefs,
    });
    final keys = FakeKeys();
    await keys.generate(
      alias: DeviceKeyStore.transportAlias,
      challenge: Uint8List(32),
      requireUserAuth: false,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          deviceKeyStoreProvider.overrideWithValue(keys),
          httpClientProvider.overrideWithValue(() => MockClient(handler)),
        ],
        child: const VouchApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  tearDown(() => PushService.instance.launchAlert = null);

  testWidgets('a new alert shows on Home and opens with its text', (
    tester,
  ) async {
    await open(tester, server([leak]));
    expect(find.text('TEST canary'), findsOneWidget);
    expect(find.text('New alert. Tap to read.'), findsOneWidget);

    await tester.tap(find.text('TEST canary'));
    await tester.pumpAndSettle();
    expect(find.text('Alerts'), findsOneWidget);
    expect(find.text('Critical'), findsOneWidget);
    expect(
      find.text('A test of the leak check. Nothing leaked.'),
      findsOneWidget,
    );

    // Opened: Home no longer marks it, and remembers that. It can still
    // be read again from Home.
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('TEST canary'), findsNothing);
    expect(find.text('1 in the last 30 days.'), findsOneWidget);
    await tester.tap(find.text('Alerts'));
    await tester.pumpAndSettle();
    expect(
      find.text('A test of the leak check. Nothing leaked.'),
      findsOneWidget,
    );
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getInt(AlertsSeen.key),
      DateTime.utc(2026, 11, 16, 19).millisecondsSinceEpoch,
    );
  });

  testWidgets('an alert already opened is not marked', (tester) async {
    await open(
      tester,
      server([leak]),
      prefs: {
        AlertsSeen.key: DateTime.utc(2026, 11, 16, 19).millisecondsSinceEpoch,
      },
    );
    expect(find.text('TEST canary'), findsNothing);
    expect(find.text('1 in the last 30 days.'), findsOneWidget);
  });

  testWidgets('without push, an alert appears when the app comes back', (
    tester,
  ) async {
    final alerts = <Map<String, Object?>>[];
    await open(tester, server(alerts));
    expect(find.text('TEST canary'), findsNothing);

    alerts.add(leak);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('TEST canary'), findsOneWidget);
  });

  testWidgets('started from an alert notification: the alert is on screen', (
    tester,
  ) async {
    PushService.instance.launchAlert = 'alt_0123456789';
    await open(tester, server([leak]));
    expect(find.text('Alerts'), findsOneWidget);
    expect(
      find.text('A test of the leak check. Nothing leaked.'),
      findsOneWidget,
    );
  });

  testWidgets('a server without the list still shows the tapped alert', (
    tester,
  ) async {
    PushService.instance.launchAlert = 'alt_0123456789';
    await open(tester, server([leak], listed: false));
    expect(find.text('TEST canary'), findsOneWidget);
    expect(find.text('No alerts in the last 30 days.'), findsNothing);
  });

  testWidgets('no alerts says so', (tester) async {
    await open(tester, server(const []));
    expect(find.text('None in the last 30 days.'), findsOneWidget);
    await tester.tap(find.text('Alerts'));
    await tester.pumpAndSettle();
    expect(find.text('No alerts in the last 30 days.'), findsOneWidget);
  });

  testWidgets('Settings also opens the alerts, read or not', (tester) async {
    await open(
      tester,
      server([leak]),
      prefs: {
        AlertsSeen.key: DateTime.utc(2026, 11, 16, 19).millisecondsSinceEpoch,
      },
    );
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Alerts'));
    await tester.pumpAndSettle();
    expect(find.text('TEST canary'), findsOneWidget);
  });
}
