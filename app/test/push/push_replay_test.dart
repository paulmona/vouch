import 'package:flutter_test/flutter_test.dart';
import 'package:vouch/push/notifications.dart';
import 'package:vouch/push/push_event.dart';
import 'package:vouch/push/push_handler.dart';

/// firebase_messaging replays its last foreground message to every
/// newly attached engine. On a real phone that re-posted the notification
/// for a request approved six minutes earlier. A request push seen before
/// is dropped: not shown, not contact, no event.
class _Notifier implements RequestNotifier {
  final shown = <String>[];
  final cleared = <String>[];
  @override
  Future<void> showRequest(
    String requestId, {
    String? title,
    String? body,
  }) async => shown.add(requestId);
  @override
  Future<void> clearRequest(String requestId) async => cleared.add(requestId);
  @override
  Future<void> showAlert(String alertId, {String? title, String? body}) async {}
}

class _Receipts implements PushReceipts {
  final seen = <String, DateTime>{};
  @override
  Future<void> recordReceived(String requestId, DateTime at) async =>
      seen[requestId] = at;
  @override
  Future<DateTime?> received(String requestId) async => seen[requestId];
}

void main() {
  const push = {'v': '1', 'kind': 'request', 'request_id': 'req_0123456789'};

  test('the same request push twice: shown once, contact once', () async {
    final n = _Notifier();
    final r = _Receipts();
    var contacts = 0;
    final h = PushHandler(
      notifier: n,
      receipts: r,
      onContact: () async => contacts++,
      now: () => DateTime.utc(2026, 11, 5, 13, 10),
    );

    expect(await h.handle(push), isA<RequestPush>());
    expect(await h.handle(push), isNull, reason: 'replay is not an event');

    expect(n.shown, ['req_0123456789']);
    expect(contacts, 1);
    expect(r.seen['req_0123456789'], DateTime.utc(2026, 11, 5, 13, 10));
  });

  test('a receipt from an earlier process also drops the push', () async {
    // Receipts live in SharedPreferences, so a replay after the process
    // restarted is caught too.
    final n = _Notifier();
    final r = _Receipts()..seen['req_0123456789'] = DateTime.utc(2026, 11, 5);
    final h = PushHandler(notifier: n, receipts: r);
    expect(await h.handle(push), isNull);
    expect(n.shown, isEmpty);
  });

  test('a clear for a seen request still goes through', () async {
    final n = _Notifier();
    final r = _Receipts()..seen['req_0123456789'] = DateTime.utc(2026, 11, 5);
    final h = PushHandler(notifier: n, receipts: r);
    expect(
      await h.handle({
        'v': '1',
        'kind': 'clear',
        'request_id': 'req_0123456789',
      }),
      isA<ClearPush>(),
    );
    expect(n.cleared, ['req_0123456789']);
  });
}
