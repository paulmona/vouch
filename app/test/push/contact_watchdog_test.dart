import 'package:flutter_test/flutter_test.dart';
import 'package:vouch/push/contact_watchdog.dart';

class _FakeScheduler implements ReminderScheduler {
  final scheduled = <({int id, DateTime at, String title, String body})>[];
  final cancelled = <int>[];

  @override
  Future<void> scheduleReminder({
    required int id,
    required DateTime at,
    required String title,
    required String body,
  }) async => scheduled.add((id: id, at: at, title: title, body: body));

  @override
  Future<void> cancelReminder(int id) async => cancelled.add(id);
}

void main() {
  final t0 = DateTime.utc(2026, 11, 5, 3, 0);

  test('hearing from the server arms the fallback 26 h later', () async {
    final s = _FakeScheduler();
    final w = ContactWatchdog(scheduler: s, now: () => t0);
    await w.heard(serverName: 'home (test)');

    final r = s.scheduled.single;
    expect(r.id, ContactWatchdog.notificationId);
    expect(r.at, t0.add(const Duration(hours: 26)));
    expect(r.title, "Haven't heard from your approver in a day");
    expect(r.body, contains('home (test)'));
  });

  test(
    'every contact replaces the previous arming (same id, later time)',
    () async {
      final s = _FakeScheduler();
      final w = ContactWatchdog(scheduler: s, now: () => t0);
      await w.heard();
      await w.heard(at: t0.add(const Duration(hours: 5)));

      expect(s.scheduled, hasLength(2));
      expect(s.scheduled[0].id, s.scheduled[1].id);
      expect(s.scheduled[1].at, t0.add(const Duration(hours: 31)));
    },
  );

  test(
    'the clock advanced past the window: the armed time has passed',
    () async {
      // The OS fires the notification; what we can prove is that the last
      // arming is before "now + 26 h + a bit" and nothing re-armed it.
      final s = _FakeScheduler();
      final w = ContactWatchdog(scheduler: s, now: () => t0);
      await w.heard();
      final later = t0.add(const Duration(hours: 27));
      expect(s.scheduled.single.at.isBefore(later), isTrue);
      expect(s.cancelled, isEmpty);
    },
  );

  test('unpairing cancels it', () async {
    final s = _FakeScheduler();
    final w = ContactWatchdog(scheduler: s, now: () => t0);
    await w.heard();
    await w.stop();
    expect(s.cancelled, [ContactWatchdog.notificationId]);
  });

  test('body names the last contact in local time', () {
    final body = ContactWatchdog.bodyFor(
      DateTime(2026, 11, 4, 21, 42),
      'home (test)',
    );
    expect(
      body,
      startsWith('Vouch last heard from home (test) at 2026-11-04 21:42.'),
    );
    expect(ContactWatchdog.bodyFor(t0, null), contains('your server'));
  });
}
