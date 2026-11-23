import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vouch/app.dart';
import 'package:vouch/keys/device_key.dart';
import 'package:vouch/pairing/device_session.dart';
import 'package:vouch/pairing/paired_device.dart';
import 'package:vouch/push/push_service.dart';
import 'package:vouch_api/api.dart';

import 'helpers/fake_keys.dart';

/// Home's server card: a dot when connected, words only when something is
/// wrong.
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

  Future<void> open(
    WidgetTester tester,
    Future<http.Response> Function(http.Request) handler, {
    bool decisionKey = true,
    bool pushAvailable = true,
  }) async {
    SharedPreferences.setMockInitialValues({
      PairedDeviceStore.key: jsonEncode(paired.toJson()),
    });
    final keys = FakeKeys();
    await keys.generate(
      alias: DeviceKeyStore.transportAlias,
      challenge: Uint8List(32),
      requireUserAuth: false,
    );
    if (decisionKey) {
      await keys.generate(
        alias: DeviceKeyStore.decisionAlias,
        challenge: Uint8List(32),
        requireUserAuth: true,
      );
    }
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          deviceKeyStoreProvider.overrideWithValue(keys),
          httpClientProvider.overrideWithValue(() => MockClient(handler)),
          pushAvailableProvider.overrideWithValue(pushAvailable),
        ],
        child: const VouchApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  http.Response json(Object body) => http.Response(
    jsonEncode(body),
    200,
    headers: {'content-type': 'application/json'},
  );

  Future<http.Response> server(http.Request r, {bool? pushEnabled}) async {
    if (r.url.path == '/v1/devices/me') {
      return json({
        'device_id': paired.deviceId,
        'name': 'Test phone',
        'platform': 'ios',
        'paired_at': '2026-11-05T00:00:00Z',
        'last_checkin_at': null,
        'user_auth_bound': 'attested',
        'policy': {'require_user_auth': true},
        'rekey_required': false,
        'push_enabled': ?pushEnabled,
      });
    }
    if (r.url.path == '/v1/requests/pending') {
      return json({'requests': <Object>[]});
    }
    return http.Response('', 404);
  }

  const noPush =
      'No notifications from this server. Open Vouch to check '
      'for requests, or pull down to refresh.';

  testWidgets('a server without push: says to open the app', (tester) async {
    await open(tester, (r) => server(r, pushEnabled: false));
    expect(find.text(noPush), findsOneWidget);
  });

  testWidgets('a build without push: says so, and how to get it', (
    tester,
  ) async {
    await open(
      tester,
      (r) => server(r, pushEnabled: false),
      pushAvailable: false,
    );
    expect(
      find.text(
        'This copy of Vouch has no notifications. Open Vouch to check for '
        'requests, or pull down to refresh. For notifications, build Vouch '
        'with your own Firebase project.',
      ),
      findsOneWidget,
    );
    expect(find.text(noPush), findsNothing);
  });

  testWidgets('a server with push, or one that does not say: nothing', (
    tester,
  ) async {
    await open(tester, (r) => server(r, pushEnabled: true));
    expect(find.text(noPush), findsNothing);
    await open(tester, server);
    expect(find.text(noPush), findsNothing);
  });

  testWidgets('connected: name, host and a dot, nothing else', (tester) async {
    await open(tester, (r) async {
      if (r.url.path == '/v1/devices/me') {
        return json({
          'device_id': paired.deviceId,
          'name': 'Test phone',
          'platform': 'ios',
          'paired_at': '2026-11-05T00:00:00Z',
          'last_checkin_at': null,
          'user_auth_bound': 'attested',
          'policy': {'require_user_auth': true},
          'rekey_required': false,
        });
      }
      if (r.url.path == '/v1/requests/pending') {
        return json({'requests': <Object>[]});
      }
      return http.Response('', 404);
    });
    expect(find.text('home-server'), findsOneWidget);
    expect(find.text('vouch.example.com'), findsOneWidget);
    expect(find.byTooltip('Connected'), findsOneWidget);
    expect(find.text('Connected'), findsNothing);
    expect(find.textContaining('Last contact'), findsNothing);
    expect(find.textContaining('Paired'), findsNothing);
  });

  testWidgets('unreachable: a red dot and the reason', (tester) async {
    await open(tester, (r) async => throw http.ClientException('offline'));
    expect(find.byTooltip('Not connected'), findsOneWidget);
    expect(find.textContaining("Couldn't reach the server"), findsOneWidget);
  });

  testWidgets('the server answers but the decision key is gone: not '
      '"Connected", and says to pair again', (tester) async {
    await open(tester, server, decisionKey: false);
    expect(find.byTooltip('Connected'), findsNothing);
    expect(find.byTooltip("Can't approve"), findsOneWidget);
    expect(
      find.text(
        'This phone no longer has its approval key. '
        'Forget this server in Settings, then pair again.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('a pending text request is listed by its number, not the '
      'name the agent gave', (tester) async {
    final t = DateTime.now().toUtc();
    final spoof = ApprovalRequest(
      requestId: 'b7c8d9e0f1a2b3c4',
      kind: ApprovalRequestKindEnum.smsContact,
      agent: 'Ava',
      site: '+19005550123',
      loginTitle: null,
      smsContact: ApprovalRequestSmsContact(
        phone: '+19005550123',
        name: '+1 (416) 555-0199',
        reason: 'Dinner.',
      ),
      createdAt: t,
      expiresAt: t.add(const Duration(hours: 1)),
      state: ApprovalRequestStateEnum.pending,
    );
    await open(tester, (r) async {
      if (r.url.path == '/v1/requests/pending') {
        return json({
          'requests': [spoof.toJson()],
        });
      }
      return server(r);
    });
    expect(find.text('Ava · text (900) 555-0123'), findsOneWidget);
    expect(find.textContaining('416'), findsNothing);
  });
}
