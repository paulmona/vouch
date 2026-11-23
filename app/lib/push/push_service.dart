import 'dart:async';
import 'dart:io' as io;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'alert_details.dart';
import 'check_in.dart';
import 'contact_watchdog.dart';
import 'notifications.dart';
import 'push_event.dart';
import 'push_handler.dart';

/// A tapped request notification: which request to open.
typedef RequestOpen = ({String requestId});

/// Runs in its own isolate when a data message arrives and the app is in
/// the background or killed. Must be a top-level function.
@pragma('vm:entry-point')
Future<void> vouchBackgroundPushHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  final notifications = VouchNotifications();
  await notifications.init();
  await backgroundPushHandler(
    notifier: notifications,
    scheduler: notifications,
  ).handle(message.data, systemShown: message.notification != null);
}

/// The handler the background isolate uses. It has no [PushHandler.onAlert]:
/// an alert that arrives while Vouch is not on screen shows Vouch's own
/// fixed text, never the sender's, so the sender's words are read only
/// inside the app. (Fetching them needs the device key, which the
/// background isolate cannot reach on Android anyway.)
@visibleForTesting
PushHandler backgroundPushHandler({
  required RequestNotifier notifier,
  required ReminderScheduler scheduler,
}) => PushHandler(
  notifier: notifier,
  receipts: PrefsPushReceipts(),
  onHeartbeat: _answerHeartbeat,
  onContact: ContactWatchdog(scheduler: scheduler).heard,
);

Future<void> _answerHeartbeat(String heartbeatId) async {
  await CheckInService().checkIn(heartbeatId: heartbeatId);
}

Future<({String title, String body})?> _alertText(String alertId) async {
  final a = await AlertDetails().fetch(alertId);
  return a == null ? null : AlertDetails.textFor(a);
}

/// Firebase Messaging plus local notifications, wired together.
///
/// The app still starts when Firebase cannot initialise (no
/// google-services.json in a dev build): [available] is then false and
/// nothing push-related runs.
class PushService {
  PushService._();

  static final instance = PushService._();

  final notifications = VouchNotifications();
  late final PushHandler handler = PushHandler(
    notifier: notifications,
    receipts: PrefsPushReceipts(),
    onHeartbeat: _answerHeartbeat,
    onAlert: _alertText,
    onContact: ContactWatchdog(scheduler: notifications).heard,
  );

  bool _initialised = false;
  bool available = false;
  String? _token;

  /// Fires when the person taps a request notification while the app is
  /// running.
  final openRequest = StreamController<RequestOpen>.broadcast();

  /// Fires with the alert id when the person taps an alert notification
  /// while the app is running.
  final openAlert = StreamController<String>.broadcast();

  /// Every push handled while the app is running, after the notification
  /// side is done. The app uses it to refresh what is on screen: a request
  /// push while Home is open must show up without a pull-down.
  final events = StreamController<PushEvent>.broadcast();
  final _tokenRefresh = StreamController<String>.broadcast();

  /// The current Firebase token, or null when Firebase is unavailable or
  /// the token has not been issued yet. Never logged.
  String? get token => _token;

  /// Firebase rotates tokens; the paired device must PUT the new one.
  Stream<String> get onTokenRefresh => _tokenRefresh.stream;

  Future<void> init() async {
    if (_initialised) return;
    _initialised = true;

    await notifications.init(onTap: _onNotificationTap);
    // init() runs before runApp, so nobody listens to [openRequest] yet: a
    // launch payload is kept until the app takes it.
    final launch = await notifications.launchResponse();
    if (launch != null) {
      _launchRequest = _openOf(launch);
      _launchAlert = _alertOf(launch.payload);
    }

    try {
      await Firebase.initializeApp();
      available = true;
    } catch (e) {
      // No Firebase config in this build. Push stays off; the rest works.
      debugPrint('Vouch: Firebase unavailable (${e.runtimeType}); push off');
      return;
    }

    FirebaseMessaging.onBackgroundMessage(vouchBackgroundPushHandler);
    FirebaseMessaging.onMessage.listen((m) => _handleForeground(m.data));
    // A tap on an alert iOS showed itself comes through Firebase, not the
    // local notifications plugin.
    FirebaseMessaging.onMessageOpenedApp.listen((m) {
      final open = _openOfRemote(m);
      if (open != null) openRequest.add(open);
      final alert = _alertOfRemote(m);
      if (alert != null) openAlert.add(alert);
    });
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) {
      _launchRequest ??= _openOfRemote(initial);
      _launchAlert ??= _alertOfRemote(initial);
    }

    // firebase_messaging 17 deprecates registration tokens in favour of
    // register()/onRegistered (a Firebase Installation ID for "direct send").
    // The contract's push_token and the server's FCM HTTP v1 sender use
    // registration tokens, so stay on them until the contract says otherwise.
    final messaging = FirebaseMessaging.instance;
    // ignore: deprecated_member_use
    messaging.onTokenRefresh.listen((t) {
      _token = t;
      _tokenRefresh.add(t);
    });
    // Never block startup on the token: FCM registration can take a long
    // time (or fail) with no network. Pairing waits for it; the UI does not.
    unawaited(_fetchToken(messaging));
    if (io.Platform.isIOS) unawaited(_logApnsRegistration(messaging));
  }

  /// FCM on iOS relays through APNs: without an APNs token every "sent"
  /// push is dropped before it reaches the phone. Logged (presence only)
  /// so a device run shows which side a silent phone is on.
  Future<void> _logApnsRegistration(FirebaseMessaging messaging) async {
    try {
      final apns = await messaging.getAPNSToken();
      debugPrint(
        'Vouch: APNs token ${apns == null ? 'missing' : 'registered'}',
      );
    } catch (e) {
      debugPrint('Vouch: APNs token lookup failed (${e.runtimeType})');
    }
  }

  Future<void> _fetchToken(FirebaseMessaging messaging) async {
    try {
      // ignore: deprecated_member_use
      final t = await messaging.getToken();
      if (t != null) {
        _token = t;
        _tokenRefresh.add(t);
      }
    } catch (e) {
      debugPrint('Vouch: no push token yet (${e.runtimeType})');
    }
  }

  /// Debug and tests: feed a payload through the same path a real push takes.
  Future<PushEvent?> simulate(Map<String, String> data) =>
      _handleForeground(data);

  Future<PushEvent?> _handleForeground(Map<Object?, Object?> data) async {
    debugPrint('Vouch: push received in the foreground (${data['kind']})');
    final event = await handler.handle(data);
    if (event != null) events.add(event);
    return event;
  }

  void _onNotificationTap(NotificationResponse r) {
    final open = _openOf(r);
    if (open != null) openRequest.add(open);
    final alert = _alertOf(r.payload);
    if (alert != null) openAlert.add(alert);
  }

  String? _launchAlert;

  /// The alert whose notification started this app, once.
  String? takeLaunchAlert() {
    final id = _launchAlert;
    _launchAlert = null;
    return id;
  }

  /// Tests: pretend the app was started from this alert's notification.
  @visibleForTesting
  set launchAlert(String? id) => _launchAlert = id;

  static String? _alertOf(String? payload) =>
      payload != null &&
          payload.startsWith(VouchNotifications.alertPayloadPrefix)
      ? payload.substring(VouchNotifications.alertPayloadPrefix.length)
      : null;

  static String? _alertOfRemote(RemoteMessage m) =>
      switch (PushEvent.parse(m.data)) {
        AlertPush(:final alertId) => alertId,
        _ => null,
      };

  RequestOpen? _launchRequest;

  /// The request whose notification started this app, once; null after
  /// that, and when the app was opened any other way.
  RequestOpen? takeLaunchRequest() {
    final open = _launchRequest;
    _launchRequest = null;
    return open;
  }

  /// Tests: pretend the app was started from this request's notification.
  @visibleForTesting
  set launchRequest(RequestOpen? open) => _launchRequest = open;

  static RequestOpen? _openOfRemote(RemoteMessage m) =>
      switch (PushEvent.parse(m.data)) {
        RequestPush(:final requestId) => (requestId: requestId),
        _ => null,
      };

  /// A request notification response as what the app should do: which
  /// request.
  static RequestOpen? _openOf(NotificationResponse r) {
    final payload = r.payload;
    if (payload == null ||
        !payload.startsWith(VouchNotifications.requestPayloadPrefix)) {
      return null;
    }
    return (
      requestId: payload.substring(
        VouchNotifications.requestPayloadPrefix.length,
      ),
    );
  }
}

/// Push receipt times in SharedPreferences, so the background isolate and
/// the app agree on when a push landed.
class PrefsPushReceipts implements PushReceipts {
  static String _key(String id) => 'push.received.$id';

  @override
  Future<void> recordReceived(String requestId, DateTime at) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_key(requestId), at.millisecondsSinceEpoch);
  }

  @override
  Future<DateTime?> received(String requestId) async {
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt(_key(requestId));
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }
}
