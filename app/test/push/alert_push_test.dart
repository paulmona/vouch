import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vouch/api/canonical.dart';
import 'package:vouch/keys/device_key.dart';
import 'package:vouch/pairing/paired_device.dart';
import 'package:vouch/push/alert_details.dart';
import 'package:vouch/push/contact_watchdog.dart';
import 'package:vouch/push/notifications.dart';
import 'package:vouch/push/push_handler.dart';
import 'package:vouch/push/push_service.dart';

import '../helpers/fake_keys.dart';

class _Notifier implements RequestNotifier {
  final alerts = <({String id, String? title, String? body})>[];
  @override
  Future<void> clearRequest(String requestId) async {}
  @override
  Future<void> showRequest(
    String requestId, {
    String? title,
    String? body,
  }) async {}
  @override
  Future<void> showAlert(String alertId, {String? title, String? body}) async =>
      alerts.add((id: alertId, title: title, body: body));
}

class _NoReminders implements ReminderScheduler {
  @override
  Future<void> scheduleReminder({
    required int id,
    required DateTime at,
    required String title,
    required String body,
  }) async {}
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
    serverName: 'home (test)',
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
    return k;
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({
      PairedDeviceStore.key: jsonEncode(paired.toJson()),
    });
  });

  PushHandler handler(
    _Notifier n,
    AlertDetails details,
    List<String> contacts,
  ) => PushHandler(
    notifier: n,
    receipts: _NoReceipts(),
    onAlert: (id) async {
      final a = await details.fetch(id);
      return a == null ? null : AlertDetails.textFor(a);
    },
    onContact: () async => contacts.add('heard'),
  );

  // On Android an alert that arrives while Vouch is not on screen is
  // handled in the background isolate. It shows Vouch's fixed text: the
  // sender's title and body are read only inside the app.
  test('in the background an alert shows the fixed text and fetches '
      'nothing', () async {
    final n = _Notifier();
    final h = backgroundPushHandler(notifier: n, scheduler: _NoReminders());
    expect(h.onAlert, isNull, reason: 'nothing may fetch the sender text');
    await h.handle({'v': '1', 'kind': 'alert', 'alert_id': 'alert_0123456789'});
    expect(n.alerts.single.id, 'alert_0123456789');
    expect(n.alerts.single.title, isNull);
    expect(n.alerts.single.body, isNull);
  });

  test('an alert push fetches its details and shows them', () async {
    final k = await keys();
    http.Request? seen;
    final details = AlertDetails(
      keys: k,
      httpClient: () => MockClient((r) async {
        seen = r;
        return http.Response(
          jsonEncode({
            'alert_id': 'alr_0123456789',
            'severity': 'critical',
            'title': 'Rejected approval attempt',
            'body': 'An unknown device tried to answer a request at 14:02.',
            'created_at': '2026-11-05T03:00:00Z',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    final n = _Notifier();
    final contacts = <String>[];
    await handler(
      n,
      details,
      contacts,
    ).handle({'v': '1', 'kind': 'alert', 'alert_id': 'alr_0123456789'});

    expect(seen!.method, 'GET');
    expect(seen!.url.path, '/v1/alerts/alr_0123456789');
    expect(seen!.headers[Canonical.headerDevice], 'dev_0123456789');
    expect(k.prompts, isEmpty, reason: 'transport key, no fingerprint');
    expect(n.alerts.single.title, 'Critical: Rejected approval attempt');
    expect(
      n.alerts.single.body,
      'An unknown device tried to answer a request at 14:02.',
    );
    expect(contacts, ['heard'], reason: 'a push counts as contact');
  });

  test('details unavailable: a generic alert still shows', () async {
    final details = AlertDetails(
      keys: await keys(),
      httpClient: () =>
          MockClient((r) async => throw http.ClientException('offline')),
    );
    final n = _Notifier();
    await handler(
      n,
      details,
      [],
    ).handle({'v': '1', 'kind': 'alert', 'alert_id': 'alr_0123456789'});
    expect(n.alerts.single.id, 'alr_0123456789');
    expect(n.alerts.single.title, isNull);
  });

  test('a malformed push is neither shown nor counted as contact', () async {
    final n = _Notifier();
    final contacts = <String>[];
    final details = AlertDetails(keys: await keys());
    await handler(n, details, contacts).handle({'v': '2', 'kind': 'alert'});
    expect(n.alerts, isEmpty);
    expect(contacts, isEmpty);
  });
}
