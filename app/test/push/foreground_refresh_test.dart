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
import 'package:vouch/push/push_event.dart';
import 'package:vouch/push/push_service.dart';

import '../helpers/fake_keys.dart';

/// A request push while Vouch is open on Home refreshes the pending list
/// by itself, with no pull to refresh.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final paired = PairedDevice(
    deviceId: 'dev_0123456789',
    serverUrl: Uri.parse('https://vouch.example.com'),
    serverName: 'home-server',
    requireUserAuth: false,
    userAuthBound: 'none',
    pairedAt: DateTime.utc(2026, 11, 5),
  );

  Map<String, Object?> request(String id) => {
    'request_id': id,
    'kind': 'sign_in',
    'agent': 'Agent test',
    'site': 'example.com',
    'login_title': 'example.com (test)',
    'created_at': '2026-11-05T13:00:00Z',
    'expires_at': '2099-01-01T00:00:00Z',
    'state': 'pending',
  };

  testWidgets('a request push refreshes Home without a pull-down', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      PairedDeviceStore.key: jsonEncode(paired.toJson()),
    });
    final keys = FakeKeys();
    await keys.generate(
      alias: DeviceKeyStore.transportAlias,
      challenge: Uint8List(32),
      requireUserAuth: false,
    );

    // The server has nothing, then (after the push) one request.
    final pending = <Map<String, Object?>>[];
    var listCalls = 0;
    Future<http.Response> handler(http.Request r) async {
      if (r.url.path == '/v1/requests/pending') {
        listCalls++;
        return http.Response(
          jsonEncode({'requests': pending}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (r.url.path == '/v1/devices/me') {
        return http.Response(
          jsonEncode({
            'device_id': paired.deviceId,
            'name': 'Test phone',
            'platform': 'android',
            'paired_at': '2026-11-05T00:00:00Z',
            'last_checkin_at': null,
            'user_auth_bound': 'none',
            'policy': {'require_user_auth': false},
            'rekey_required': false,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('', 204);
    }

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
    expect(find.text('Pending requests'), findsNothing);
    final before = listCalls;

    pending.add(request('req_0123456789'));
    PushService.instance.events.add(const RequestPush('req_0123456789'));
    await tester.pumpAndSettle();

    expect(listCalls, greaterThan(before), reason: 'the list was re-fetched');
    expect(find.text('Agent test · example.com'), findsOneWidget);
    expect(find.text('Pending requests'), findsOneWidget);

    // The request was decided elsewhere: a clear push takes it off the list.
    pending.clear();
    PushService.instance.events.add(const ClearPush('req_0123456789'));
    await tester.pumpAndSettle();
    expect(find.text('Pending requests'), findsNothing);
  });

  // An open request that another device answers, or that ends, stops
  // offering its buttons when the clear push arrives.
  testWidgets('a clear push settles the request screen that is open', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      PairedDeviceStore.key: jsonEncode(paired.toJson()),
    });
    final keys = FakeKeys();
    await keys.generate(
      alias: DeviceKeyStore.transportAlias,
      challenge: Uint8List(32),
      requireUserAuth: false,
    );

    var current = request('req_0123456789');
    Future<http.Response> handler(http.Request r) async {
      final json = switch (r.url.path) {
        '/v1/requests/pending' => {
          'requests': [if (current['state'] == 'pending') current],
        },
        '/v1/requests/req_0123456789' => current,
        _ => null,
      };
      return json == null
          ? http.Response('', 204)
          : http.Response(
              jsonEncode(json),
              200,
              headers: {'content-type': 'application/json'},
            );
    }

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
    await tester.tap(find.text('Agent test · example.com'));
    await tester.pumpAndSettle();
    expect(find.text('Deny'), findsOneWidget);

    // Denied on the owner's other phone.
    current = {...current, 'state': 'deny', 'decided_by': 'other_device'};
    PushService.instance.events.add(const ClearPush('req_0123456789'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Answered on another device'), findsOneWidget);
    expect(find.text('Deny'), findsNothing);
    expect(find.text('Approve once'), findsNothing);
  });

  testWidgets('heartbeat and alert pushes leave the list alone', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      PairedDeviceStore.key: jsonEncode(paired.toJson()),
    });
    final keys = FakeKeys();
    await keys.generate(
      alias: DeviceKeyStore.transportAlias,
      challenge: Uint8List(32),
      requireUserAuth: false,
    );
    var listCalls = 0;
    Future<http.Response> handler(http.Request r) async {
      if (r.url.path == '/v1/requests/pending') listCalls++;
      return http.Response(
        jsonEncode({'requests': <Object>[]}),
        200,
        headers: {'content-type': 'application/json'},
      );
    }

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
    final before = listCalls;

    PushService.instance.events.add(const HeartbeatPush('hb_0123456789'));
    PushService.instance.events.add(const AlertPush('alr_0123456789'));
    await tester.pumpAndSettle();
    expect(listCalls, before);
  });
}
