import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'push_service.dart';

/// Schedules one local notification for later, or cancels it. An interface
/// so the watchdog is unit-testable without Android.
abstract class ReminderScheduler {
  Future<void> scheduleReminder({
    required int id,
    required DateTime at,
    required String title,
    required String body,
  });

  Future<void> cancelReminder(int id);
}

/// The 26-hour fallback: every time the phone hears from the server,
/// a local notification is re-armed for 26 hours later. If the server dies,
/// nothing re-arms it and it fires on its own: "Haven't heard from your
/// approver in a day." Stopped on unpair.
class ContactWatchdog {
  ContactWatchdog({
    required this.scheduler,
    this.after = const Duration(hours: 26),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  /// One slot: each re-arm replaces the last.
  static const notificationId = 0x56415443; // "VATC"

  static const title = "Haven't heard from your approver in a day";

  final ReminderScheduler scheduler;
  final Duration after;
  final DateTime Function() _now;

  /// The server was heard from at [at] (default: now). Re-arms the fallback.
  Future<void> heard({DateTime? at, String? serverName}) async {
    final t = at ?? _now();
    await scheduler.scheduleReminder(
      id: notificationId,
      at: t.add(after),
      title: title,
      body: bodyFor(t, serverName),
    );
  }

  /// Unpaired: no server to miss.
  Future<void> stop() => scheduler.cancelReminder(notificationId);

  static String bodyFor(DateTime lastContact, String? serverName) {
    final l = lastContact.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    final when =
        '${l.year}-${two(l.month)}-${two(l.day)} ${two(l.hour)}:${two(l.minute)}';
    return 'Vouch last heard from ${serverName ?? 'your server'} at $when. '
        'Check that it is running and that this phone can reach it.';
  }
}

/// The app's watchdog, scheduling through the real notification plugin.
final contactWatchdogProvider = Provider<ContactWatchdog>(
  (ref) => ContactWatchdog(scheduler: PushService.instance.notifications),
);
