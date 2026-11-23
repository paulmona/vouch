import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vouch/screens/notification_health_screen.dart';
import 'package:vouch/theme/vouch_theme.dart';

/// Stands in for Android's notification settings.
class _Android extends AndroidFlutterLocalNotificationsPlugin {
  @override
  Future<bool?> areNotificationsEnabled() async => true;
}

void main() {
  setUp(() => FlutterLocalNotificationsPlatform.instance = _Android());

  // A sign-in lasts minutes, a request to text someone new lasts hours, so
  // the time limit is described without a number.
  testWidgets('the time limit is stated without a number of minutes', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: VouchTheme.light(),
        home: const NotificationHealthScreen(),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text(
        'A request is time-limited: if nobody answers it in time, it is '
        'denied.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('minute'), findsNothing);
  });
}
