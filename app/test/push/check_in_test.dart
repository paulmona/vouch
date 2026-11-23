import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vouch/api/canonical.dart';
import 'package:vouch/api/device_signer.dart';
import 'package:vouch/keys/device_key.dart';
import 'package:vouch/pairing/paired_device.dart';
import 'package:vouch/push/check_in.dart';
import 'package:vouch/push/contact_watchdog.dart';
import 'package:vouch/push/notifications.dart';
import 'package:vouch/push/push_handler.dart';

import '../helpers/fake_keys.dart';

class _NoNotifier implements RequestNotifier {
  @override
  Future<void> clearRequest(String requestId) async {}
  @override
  Future<void> showRequest(
    String requestId, {
    String? title,
    String? body,
  }) async {}
  @override
  Future<void> showAlert(String alertId, {String? title, String? body}) async {}
}

class _Reminders implements ReminderScheduler {
  final scheduled = <int>[];

  @override
  Future<void> scheduleReminder({
    required int id,
    required DateTime at,
    required String title,
    required String body,
  }) async => scheduled.add(id);

  @override
  Future<void> cancelReminder(int id) async {}
}

class _NoReceipts implements PushReceipts {
  @override
  Future<void> recordReceived(String requestId, DateTime at) async {}
  @override
  Future<DateTime?> received(String requestId) async => null;
}

void main() {
  final paired = PairedDevice(
    deviceId: 'dev_0123456789',
    serverUrl: Uri.parse('http://10.0.0.20:8771'),
    serverName: 'approver-test',
    requireUserAuth: false,
    userAuthBound: 'none',
    pairedAt: DateTime.utc(2026, 11, 5),
  );

  Future<FakeKeys> keys() async {
    final k = FakeKeys();
    await k.generate(
      alias: DeviceKeyStore.transportAlias,
      challenge: Uint8List(32),
      requireUserAuth: false,
    );
    await k.generate(
      alias: DeviceKeyStore.decisionAlias,
      challenge: Uint8List(32),
      requireUserAuth: true,
    );
    return k;
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({
      PairedDeviceStore.key: jsonEncode(paired.toJson()),
    });
  });

  test('a heartbeat push posts its id, signed by the transport key', () async {
    final k = await keys();
    http.Request? seen;
    final service = CheckInService(
      keys: k,
      httpClient: () => MockClient((r) async {
        seen = r;
        return http.Response('', 204);
      }),
    );
    final handler = PushHandler(
      notifier: _NoNotifier(),
      receipts: _NoReceipts(),
      onHeartbeat: (id) async => service.checkIn(heartbeatId: id),
    );

    await handler.handle({
      'v': '1',
      'kind': 'heartbeat',
      'heartbeat_id': 'hb_0123456789',
    });

    final r = seen!;
    expect(r.method, 'POST');
    expect(r.url.toString(), 'http://10.0.0.20:8771/v1/devices/me/checkin');
    expect(utf8.decode(r.bodyBytes), '{"heartbeat_id":"hb_0123456789"}');
    expect(r.headers[Canonical.headerDevice], 'dev_0123456789');
    expect(k.prompts, isEmpty, reason: 'transport key: no fingerprint');

    final canonical = Canonical.string(
      method: r.method,
      target: Canonical.target(r.url),
      bodySha256: Canonical.bodySha256Hex(r.bodyBytes),
      timestamp: r.headers[Canonical.headerTimestamp]!,
      nonce: r.headers[Canonical.headerNonce]!,
    );
    final sig = Canonical.base64UrlDecode(
      r.headers[Canonical.headerSignature]!,
    );
    final msg = Uint8List.fromList(canonical.codeUnits);
    final transport = await k.publicKeySpki(DeviceKeyStore.transportAlias);
    final decision = await k.publicKeySpki(DeviceKeyStore.decisionAlias);
    expect(EcdsaVerifier.fromSpki(transport).verify(msg, sig), isTrue);
    expect(EcdsaVerifier.fromSpki(decision).verify(msg, sig), isFalse);
  });

  for (final (push, armed) in [(true, 1), (false, 0)]) {
    test('a check-in re-arms the day-of-silence reminder only with push '
        '(push $push)', () async {
      SharedPreferences.setMockInitialValues({
        PairedDeviceStore.key: jsonEncode(
          paired.copyWith(pushEnabled: push).toJson(),
        ),
      });
      final reminders = _Reminders();
      final service = CheckInService(
        keys: await keys(),
        httpClient: () => MockClient((r) async => http.Response('', 204)),
        watchdog: ContactWatchdog(scheduler: reminders),
      );
      expect(await service.checkIn(), isTrue);
      expect(reminders.scheduled, hasLength(armed));
    });
  }

  test('an app-open check-in sends null', () async {
    http.Request? seen;
    final service = CheckInService(
      keys: await keys(),
      httpClient: () => MockClient((r) async {
        seen = r;
        return http.Response('', 204);
      }),
    );
    expect(await service.checkIn(), isTrue);
    expect(utf8.decode(seen!.bodyBytes), '{"heartbeat_id":null}');
  });

  test(
    'a heartbeat that could not be answered is sent with the next check-in',
    () async {
      final k = await keys();
      var fail = true;
      final bodies = <String>[];
      final service = CheckInService(
        keys: k,
        httpClient: () => MockClient((r) async {
          if (fail) throw http.ClientException('offline');
          bodies.add(utf8.decode(r.bodyBytes));
          return http.Response('', 204);
        }),
      );
      expect(await service.checkIn(heartbeatId: 'hb_2222222222'), isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(CheckInService.pendingKey), 'hb_2222222222');

      fail = false;
      expect(await service.checkIn(), isTrue);
      expect(bodies, ['{"heartbeat_id":"hb_2222222222"}']);
      expect(prefs.getString(CheckInService.pendingKey), isNull);
    },
  );

  test('unpaired: nothing is sent', () async {
    SharedPreferences.setMockInitialValues({});
    var calls = 0;
    final service = CheckInService(
      keys: await keys(),
      httpClient: () => MockClient((r) async {
        calls++;
        return http.Response('', 204);
      }),
    );
    expect(await service.checkIn(heartbeatId: 'hb_3333333333'), isFalse);
    expect(calls, 0);
  });
}
