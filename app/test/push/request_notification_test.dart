import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vouch/push/notifications.dart';

/// Records what would be shown instead of talking to Android.
class _RecordingPlugin implements FlutterLocalNotificationsPlugin {
  NotificationDetails? shown;
  String? title;
  String? body;
  InitializationSettings? settings;

  @override
  Future<bool?> initialize({
    required InitializationSettings settings,
    DidReceiveNotificationResponseCallback? onDidReceiveNotificationResponse,
    DidReceiveBackgroundNotificationResponseCallback?
    onDidReceiveBackgroundNotificationResponse,
  }) async {
    this.settings = settings;
    return true;
  }

  @override
  T? resolvePlatformSpecificImplementation<
    T extends FlutterLocalNotificationsPlatform
  >() => null;

  @override
  Future<void> show({
    required int id,
    String? title,
    String? body,
    NotificationDetails? notificationDetails,
    String? payload,
  }) async {
    shown = notificationDetails;
    this.title = title;
    this.body = body;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  // The request notification is private, so whether its agent and site show
  // on the lock screen follows the owner's setting for sensitive content.
  test(
    'a request notification follows the lock-screen privacy setting',
    () async {
      final plugin = _RecordingPlugin();
      await VouchNotifications(plugin: plugin).showRequest(
        'req_0123456789',
        title: 'Example agent',
        body: 'Sign in to example.com',
      );
      final android = plugin.shown!.android!;
      expect(android.visibility, NotificationVisibility.private);
      // No full-screen intent: a request is answered on an unlocked phone,
      // so it alerts like any urgent notification instead of trying to
      // take over the lock screen.
      expect(android.fullScreenIntent, isFalse);
    },
  );

  // The notification only opens the request: deciding happens on the
  // request screen, where the request is read, so the notification carries
  // no Approve or Deny button.
  test('a request notification has no decision buttons', () async {
    final plugin = _RecordingPlugin();
    await VouchNotifications(plugin: plugin).showRequest('req_0123456789');
    final android = plugin.shown!.android!;
    expect(android.actions ?? const [], isEmpty);
    expect(
      plugin.shown!.iOS!.categoryIdentifier,
      VouchNotifications.requestCategory,
    );
  });

  // The same text serves a sign-in, which lasts minutes, and a request to
  // text someone new, which lasts hours, so it gives no time at all.
  test('the request notification text claims no expiry time', () async {
    final plugin = _RecordingPlugin();
    await VouchNotifications(plugin: plugin).showRequest('req_0123456789');
    expect(plugin.title, 'Approval request');
    expect(plugin.body, 'An agent is asking for approval. Tap to review.');
  });

  // What an alert shows when the sender's words are not fetched, as in the
  // background: Vouch's own text, nothing the sender chose.
  test('an alert without fetched text shows Vouch\'s fixed text', () async {
    final plugin = _RecordingPlugin();
    await VouchNotifications(plugin: plugin).showAlert('alert_0123456789');
    expect(plugin.title, 'Vouch alert');
    expect(
      plugin.body,
      'Your server reported a problem. Open Vouch for details.',
    );
  });

  // iOS keeps a category's buttons until the app registers it again, so the
  // category stays registered, with no actions, to clear them on upgrade.
  test('iOS registers the request category with no actions', () async {
    final plugin = _RecordingPlugin();
    await VouchNotifications(plugin: plugin).init();
    final categories = plugin.settings!.iOS!.notificationCategories;
    final request = categories.singleWhere(
      (c) => c.identifier == VouchNotifications.requestCategory,
    );
    expect(request.actions, isEmpty);
  });
}
