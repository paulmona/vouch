import 'package:flutter_test/flutter_test.dart';
import 'package:vouch/push/notifications.dart';
import 'package:vouch/push/push_event.dart';
import 'package:vouch/push/push_handler.dart';

class _FakeNotifier implements RequestNotifier {
  final shown = <String>[];
  final cleared = <String>[];
  final alerts = <String>[];

  @override
  Future<void> showRequest(
    String requestId, {
    String? title,
    String? body,
  }) async => shown.add(requestId);

  @override
  Future<void> clearRequest(String requestId) async => cleared.add(requestId);

  @override
  Future<void> showAlert(String alertId, {String? title, String? body}) async =>
      alerts.add(alertId);
}

class _FakeReceipts implements PushReceipts {
  final seen = <String, DateTime>{};
  @override
  Future<void> recordReceived(String requestId, DateTime at) async =>
      seen[requestId] = at;

  @override
  Future<DateTime?> received(String requestId) async => seen[requestId];
}

void main() {
  group('PushEvent.parse', () {
    test('the four kinds from the contract', () {
      expect(
        PushEvent.parse({
          'v': '1',
          'kind': 'request',
          'request_id': 'abcdefgh',
        }),
        isA<RequestPush>().having((e) => e.requestId, 'id', 'abcdefgh'),
      );
      expect(
        PushEvent.parse({'v': '1', 'kind': 'clear', 'request_id': 'abcdefgh'}),
        isA<ClearPush>(),
      );
      expect(
        PushEvent.parse({
          'v': '1',
          'kind': 'heartbeat',
          'heartbeat_id': 'hb_12345',
        }),
        isA<HeartbeatPush>().having((e) => e.heartbeatId, 'id', 'hb_12345'),
      );
      expect(
        PushEvent.parse({'v': '1', 'kind': 'alert', 'alert_id': 'alert-0001'}),
        isA<AlertPush>(),
      );
    });

    test('rejects other versions, kinds, missing or malformed ids', () {
      expect(
        PushEvent.parse({
          'v': '2',
          'kind': 'request',
          'request_id': 'abcdefgh',
        }),
        isNull,
      );
      expect(
        PushEvent.parse({'kind': 'request', 'request_id': 'abcdefgh'}),
        isNull,
      );
      expect(
        PushEvent.parse({'v': '1', 'kind': 'bogus', 'request_id': 'abcdefgh'}),
        isNull,
      );
      expect(PushEvent.parse({'v': '1', 'kind': 'request'}), isNull);
      expect(
        PushEvent.parse({'v': '1', 'kind': 'request', 'request_id': 'short'}),
        isNull,
      );
      expect(
        PushEvent.parse({
          'v': '1',
          'kind': 'request',
          'request_id': 'has space!',
        }),
        isNull,
      );
      expect(
        PushEvent.parse({'v': '1', 'kind': 'request', 'request_id': 42}),
        isNull,
      );
      expect(PushEvent.parse({}), isNull);
    });
  });

  group('PushHandler', () {
    late _FakeNotifier notifier;
    late _FakeReceipts receipts;
    late PushHandler handler;
    final t0 = DateTime.utc(2026, 11, 4, 18);

    setUp(() {
      notifier = _FakeNotifier();
      receipts = _FakeReceipts();
      handler = PushHandler(
        notifier: notifier,
        receipts: receipts,
        now: () => t0,
      );
    });

    test(
      'request: records the receipt time and shows the notification',
      () async {
        final e = await handler.handle({
          'v': '1',
          'kind': 'request',
          'request_id': 'r1r1r1r1',
        });
        expect(e, isA<RequestPush>());
        expect(notifier.shown, ['r1r1r1r1']);
        expect(receipts.seen['r1r1r1r1'], t0);
      },
    );

    test('clear: takes the notification down, nothing recorded', () async {
      await handler.handle({
        'v': '1',
        'kind': 'clear',
        'request_id': 'r1r1r1r1',
      });
      expect(notifier.cleared, ['r1r1r1r1']);
      expect(notifier.shown, isEmpty);
      expect(receipts.seen, isEmpty);
    });

    test('alert: shows an alert notification', () async {
      await handler.handle({
        'v': '1',
        'kind': 'alert',
        'alert_id': 'alert-0001',
      });
      expect(notifier.alerts, ['alert-0001']);
    });

    test('heartbeat: nothing visible', () async {
      final e = await handler.handle({
        'v': '1',
        'kind': 'heartbeat',
        'heartbeat_id': 'hb_12345',
      });
      expect(e, isA<HeartbeatPush>());
      expect(notifier.shown, isEmpty);
      expect(notifier.alerts, isEmpty);
    });

    test('garbage is ignored', () async {
      expect(await handler.handle({'foo': 'bar'}), isNull);
      expect(notifier.shown, isEmpty);
    });

    test(
      'request iOS already showed: receipt recorded, no second notification',
      () async {
        final e = await handler.handle({
          'v': '1',
          'kind': 'request',
          'request_id': 'abcdefgh',
        }, systemShown: true);
        expect(e, isA<RequestPush>());
        expect(notifier.shown, isEmpty);
        expect(receipts.seen['abcdefgh'], t0);
      },
    );

    test('alert iOS already showed: not shown twice', () async {
      await handler.handle({
        'v': '1',
        'kind': 'alert',
        'alert_id': 'alert-0001',
      }, systemShown: true);
      expect(notifier.alerts, isEmpty);
    });

    test('clear still clears when iOS showed the request', () async {
      await handler.handle({
        'v': '1',
        'kind': 'clear',
        'request_id': 'abcdefgh',
      }, systemShown: true);
      expect(notifier.cleared, ['abcdefgh']);
    });
  });

  test('notification ids are stable, positive and distinct', () {
    final a = VouchNotifications.notificationId('3f9c2a7b1d4e8f60');
    expect(a, VouchNotifications.notificationId('3f9c2a7b1d4e8f60'));
    expect(a, greaterThan(0));
    expect(a, isNot(VouchNotifications.notificationId('3f9c2a7b1d4e8f61')));
    expect(
      a,
      isNot(VouchNotifications.notificationId('alert:3f9c2a7b1d4e8f60')),
    );
  });
}
