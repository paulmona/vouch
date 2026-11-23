import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/vouch_api_client.dart';
import '../pairing/device_session.dart';
import '../text/shown_text.dart';

/// The server's alerts from the last 30 days, newest first. Fetched when
/// Home or the Alerts screen shows, on resume and on an alert push, so a
/// server without push still gets them seen.
final alertsProvider = FutureProvider.autoDispose<List<Alert>>((ref) async {
  final api = ref.watch(transportApiProvider);
  if (api == null) return const [];
  try {
    return (await api.alerts.listAlerts())?.alerts ?? const [];
  } on ApiException catch (e) {
    // A server from before the list existed: no list, not an error. A
    // notification still opens its own alert by id.
    if (e.code == 404) return const [];
    rethrow;
  }
});

/// One alert by id, for a notification whose alert is not in the list.
final alertProvider = FutureProvider.autoDispose.family<Alert?, String>((
  ref,
  id,
) async {
  final api = ref.watch(transportApiProvider);
  if (api == null) return null;
  try {
    return await api.alerts.getAlert(id);
  } on ApiException catch (e) {
    if (e.code == 404) return null;
    rethrow;
  }
});

/// The newest alert time the owner has looked at. Anything later is new.
class AlertsSeen extends AsyncNotifier<DateTime?> {
  static const key = 'alerts.seen_up_to';

  @override
  Future<DateTime?> build() async {
    final ms = (await SharedPreferences.getInstance()).getInt(key);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  /// The Alerts screen showed [alerts]: they are no longer new.
  Future<void> markSeen(List<Alert> alerts) async {
    if (alerts.isEmpty) return;
    final newest = alerts
        .map((a) => a.createdAt)
        .reduce((a, b) => a.isAfter(b) ? a : b);
    final current = state.value;
    if (current != null && !newest.isAfter(current)) return;
    state = AsyncData(newest);
    await (await SharedPreferences.getInstance()).setInt(
      key,
      newest.millisecondsSinceEpoch,
    );
  }
}

final alertsSeenProvider = AsyncNotifierProvider<AlertsSeen, DateTime?>(
  AlertsSeen.new,
);

/// Alerts the owner has not opened yet, newest first.
final newAlertsProvider = Provider.autoDispose<List<Alert>>((ref) {
  final alerts = ref.watch(alertsProvider).value ?? const [];
  final seen = ref.watch(alertsSeenProvider);
  if (seen.isLoading) return const [];
  final upTo = seen.value;
  return [
    for (final a in alerts)
      if (upTo == null || a.createdAt.isAfter(upTo)) a,
  ];
});

/// An alert's words as the phone shows them, hidden characters marked.
extension ShownAlert on Alert {
  String get shownTitle => ShownText.oneLine(title);
  String get shownBody => ShownText.lines(body);
}
