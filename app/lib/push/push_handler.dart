import 'notifications.dart';
import 'push_event.dart';

/// Where the handler records when a push arrived, for the push-to-screen
/// measurement (target: under 5 s). Keyed by request id.
abstract class PushReceipts {
  Future<void> recordReceived(String requestId, DateTime at);

  /// When a push for this request was first received, or null if never.
  Future<DateTime?> received(String requestId);
}

/// Turns a push into what the phone shows. Shared by the foreground
/// listener and the background isolate, and unit-tested on its own.
class PushHandler {
  PushHandler({
    required this.notifier,
    required this.receipts,
    this.onHeartbeat,
    this.onAlert,
    this.onContact,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final RequestNotifier notifier;
  final PushReceipts receipts;

  /// Answers a heartbeat push: `POST /v1/devices/me/checkin` with its
  /// id. Nothing is shown.
  final Future<void> Function(String heartbeatId)? onHeartbeat;

  /// Fetches the words behind an alert push; null shows a generic one.
  final Future<({String title, String body})?> Function(String alertId)?
  onAlert;

  /// Any valid push means the server is alive: re-arm the 26 h fallback.
  final Future<void> Function()? onContact;
  final DateTime Function() _now;

  /// Returns the parsed event, or null when the payload was not a Vouch push.
  ///
  /// [systemShown]: iOS already put up the push's own alert (a request or
  /// alert sent as a visible APNs alert while the app was in the
  /// background), so posting ours as well would show it twice.
  Future<PushEvent?> handle(
    Map<Object?, Object?> data, {
    bool systemShown = false,
  }) async {
    final event = PushEvent.parse(data);
    switch (event) {
      case RequestPush(:final requestId):
        // firebase_messaging replays its last foreground message to every
        // newly attached engine (LiveData + observeForever), so a request
        // seen once can arrive again after the activity is recreated. A
        // second push for the same request is a replay: nothing to show,
        // and not a sign of life from the server.
        if (await receipts.received(requestId) != null) return null;
        await receipts.recordReceived(requestId, _now());
        if (!systemShown) await notifier.showRequest(requestId);
      case ClearPush(:final requestId):
        await notifier.clearRequest(requestId);
      case AlertPush(:final alertId):
        if (systemShown) break;
        final text = await onAlert?.call(alertId);
        await notifier.showAlert(alertId, title: text?.title, body: text?.body);
      case HeartbeatPush(:final heartbeatId):
        await onHeartbeat?.call(heartbeatId);
      case SmsUpdatedPush():
        // The open app refetches on PushService.events; closed, it fetches
        // when next opened.
        break;
      case null:
        break;
    }
    if (event != null) await onContact?.call();
    return event;
  }
}
