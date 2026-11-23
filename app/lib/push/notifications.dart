import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../platform/biometry.dart';
import 'contact_watchdog.dart';
import 'push_service.dart';

/// What the push handler needs from the notification layer. An interface so
/// the handler is unit-testable without Android.
abstract class RequestNotifier {
  /// A new request: an urgent notification; a tap opens the request.
  Future<void> showRequest(String requestId, {String? title, String? body});

  /// The request ended elsewhere: take the notification down.
  Future<void> clearRequest(String requestId);

  /// An alert from the server (details come over the API later).
  Future<void> showAlert(String alertId, {String? title, String? body});
}

/// Notifications via flutter_local_notifications: Android channels, or iOS
/// time-sensitive notifications. A request notification has no buttons: a
/// tap opens the request, and the decision is made there.
class VouchNotifications implements RequestNotifier, ReminderScheduler {
  VouchNotifications({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  static const requestsChannel = AndroidNotificationChannel(
    'requests',
    'Approval requests',
    description: 'An agent is asking for approval. Time-limited.',
    importance: Importance.max,
  );

  static const alertsChannel = AndroidNotificationChannel(
    'alerts',
    'Alerts',
    description: 'Problems your Vouch server wants you to know about.',
    importance: Importance.high,
  );

  /// How long a request notification stays before Android removes it on
  /// its own, matching the server's 5-minute expiry.
  static const requestTimeout = Duration(minutes: 5);

  /// Payload prefix on a request notification; the app routes on tap.
  static const requestPayloadPrefix = 'request:';

  static const alertPayloadPrefix = 'alert:';
  static const watchdogPayload = 'watchdog';

  /// iOS notification category for requests. It has no actions; it stays
  /// registered so the buttons an older build registered are replaced.
  static const requestCategory = 'VOUCH_REQUEST';
  static const _requestThread = 'requests';
  static const _alertThread = 'alerts';

  /// Must run once per isolate (the main app and the background handler).
  Future<void> init({
    void Function(NotificationResponse response)? onTap,
    void Function(NotificationResponse response)? onBackgroundTap,
  }) async {
    tzdata.initializeTimeZones();
    await _plugin.initialize(
      settings: InitializationSettings(
        android: const AndroidInitializationSettings('ic_launcher_monochrome'),
        iOS: DarwinInitializationSettings(
          // Permission is asked for during pairing, not at first launch.
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
          notificationCategories: [
            DarwinNotificationCategory(requestCategory, actions: const []),
          ],
        ),
      ),
      onDidReceiveNotificationResponse: onTap,
      onDidReceiveBackgroundNotificationResponse: onBackgroundTap,
    );
    final android = _android;
    if (android != null) {
      await android.createNotificationChannel(requestsChannel);
      await android.createNotificationChannel(alertsChannel);
    }
  }

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  IOSFlutterLocalNotificationsPlugin? get _ios => _plugin
      .resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin
      >();

  /// If the app was started by tapping a notification, that response.
  Future<NotificationResponse?> launchResponse() async {
    final d = await _plugin.getNotificationAppLaunchDetails();
    if (d?.didNotificationLaunchApp != true) return null;
    return d?.notificationResponse;
  }

  @override
  Future<void> showRequest(
    String requestId, {
    String? title,
    String? body,
  }) async {
    await _plugin.show(
      id: notificationId(requestId),
      title: title ?? 'Approval request',
      body: body ?? 'An agent is asking for approval. Tap to review.',
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          requestsChannel.id,
          requestsChannel.name,
          channelDescription: requestsChannel.description,
          importance: Importance.max,
          priority: Priority.max,
          category: AndroidNotificationCategory.alarm,
          // Private: the owner's lock-screen setting decides whether the
          // agent and site show there.
          visibility: NotificationVisibility.private,
          timeoutAfter: requestTimeout.inMilliseconds,
          autoCancel: true,
          ticker: 'Approval request',
        ),
        iOS: const DarwinNotificationDetails(
          categoryIdentifier: requestCategory,
          threadIdentifier: _requestThread,
          interruptionLevel: InterruptionLevel.timeSensitive,
          presentAlert: true,
          presentBanner: true,
          presentSound: true,
        ),
      ),
      payload: '$requestPayloadPrefix$requestId',
    );
  }

  @override
  Future<void> clearRequest(String requestId) =>
      _plugin.cancel(id: notificationId(requestId));

  @override
  Future<void> showAlert(String alertId, {String? title, String? body}) async {
    await _plugin.show(
      id: notificationId('alert:$alertId'),
      title: title ?? 'Vouch alert',
      body: body ?? 'Your server reported a problem. Open Vouch for details.',
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          alertsChannel.id,
          alertsChannel.name,
          channelDescription: alertsChannel.description,
          importance: Importance.high,
          priority: Priority.high,
          category: AndroidNotificationCategory.error,
        ),
        iOS: const DarwinNotificationDetails(
          threadIdentifier: _alertThread,
          interruptionLevel: InterruptionLevel.active,
        ),
      ),
      payload: '$alertPayloadPrefix$alertId',
    );
  }

  /// The 26 h fallback: inexact so no exact-alarm permission is
  /// needed; a few minutes either way do not matter for "a day". Scheduling
  /// must never take the app down, so failures are logged and swallowed.
  @override
  Future<void> scheduleReminder({
    required int id,
    required DateTime at,
    required String title,
    required String body,
  }) async {
    try {
      await _plugin.zonedSchedule(
        id: id,
        title: title,
        body: body,
        scheduledDate: tz.TZDateTime.from(at.toUtc(), tz.UTC),
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            alertsChannel.id,
            alertsChannel.name,
            channelDescription: alertsChannel.description,
            importance: Importance.high,
            priority: Priority.high,
            category: AndroidNotificationCategory.status,
          ),
          iOS: const DarwinNotificationDetails(
            threadIdentifier: _alertThread,
            interruptionLevel: InterruptionLevel.active,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: watchdogPayload,
      );
    } on Object catch (e) {
      debugPrint(
        'Vouch: could not arm the contact watchdog (${e.runtimeType})',
      );
    }
  }

  @override
  Future<void> cancelReminder(int id) async {
    try {
      await _plugin.cancel(id: id);
    } on Object catch (e) {
      debugPrint(
        'Vouch: could not cancel the contact watchdog (${e.runtimeType})',
      );
    }
  }

  Future<bool> notificationsEnabled() async {
    if (Biometry.isApple) {
      return (await _ios?.checkPermissions())?.isEnabled ?? false;
    }
    return await _android?.areNotificationsEnabled() ?? false;
  }

  Future<bool> requestNotificationsPermission() async {
    if (Biometry.isApple) {
      return await _ios?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          false;
    }
    return await _android?.requestNotificationsPermission() ?? false;
  }

  /// A stable 31-bit notification id per request id.
  static int notificationId(String key) {
    var h = 0x811c9dc5;
    for (final c in key.codeUnits) {
      h ^= c;
      h = (h * 0x01000193) & 0x7fffffff;
    }
    return h;
  }
}

/// The app's notifier; overridable in tests.
final requestNotifierProvider = Provider<RequestNotifier>(
  (ref) => PushService.instance.notifications,
);
