import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vouch/pairing/paired_device.dart';
import 'package:vouch/screens/settings_screen.dart';
import 'package:vouch/theme/vouch_theme.dart';

/// The server's user-auth policy shows only when it is off.
void main() {
  Future<void> open(
    WidgetTester tester, {
    required bool requireAuth,
    String server = 'https://vouch.example.com',
    bool pushEnabled = true,
  }) async {
    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues({});
      await PairedDeviceStore().save(
        PairedDevice(
          deviceId: 'dev_0123456789',
          serverUrl: Uri.parse(server),
          serverName: 'home-server',
          requireUserAuth: requireAuth,
          userAuthBound: 'attested',
          pairedAt: DateTime.utc(2026, 11, 15),
          pushEnabled: pushEnabled,
        ),
      );
    });
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: VouchTheme.light(),
          home: const SettingsScreen(),
        ),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
  }

  testWidgets('on: nothing said about it', (tester) async {
    await open(tester, requireAuth: true);
    expect(find.text('Forget this server'), findsOneWidget);
    expect(find.textContaining('is off on home-server'), findsNothing);
    expect(find.textContaining('required'), findsNothing);
  });

  testWidgets('off: a warning', (tester) async {
    await open(tester, requireAuth: false);
    expect(find.textContaining('is off on home-server'), findsOneWidget);
  });

  testWidgets('a plain HTTP server is marked', (tester) async {
    await open(tester, requireAuth: true, server: 'http://192.168.1.20:8771');
    expect(find.text('Not encrypted'), findsOneWidget);
  });

  testWidgets('an https server is not', (tester) async {
    await open(tester, requireAuth: true);
    expect(find.text('Not encrypted'), findsNothing);
  });

  testWidgets('no Notifications section for a server without push', (
    tester,
  ) async {
    await open(tester, requireAuth: true, pushEnabled: false);
    expect(find.text('Notification health'), findsNothing);
    expect(find.text('Forget this server'), findsOneWidget);
  });

  testWidgets('Notifications section with push', (tester) async {
    await open(tester, requireAuth: true);
    expect(find.text('Notification health'), findsOneWidget);
  });

  // Android has no full-screen request any more; the row lists only what
  // Notification health checks.
  testWidgets('Notification health promises no full-screen permission', (
    tester,
  ) async {
    await open(tester, requireAuth: true);
    expect(find.textContaining('full-screen'), findsNothing);
    expect(find.text('Notification and battery permissions.'), findsOneWidget);
  });

  testWidgets('Forget says what it does and what the server keeps', (
    tester,
  ) async {
    await open(tester, requireAuth: true);
    await tester.ensureVisible(find.text('Forget this server'));
    await tester.tap(find.text('Forget this server'));
    await tester.pumpAndSettle();
    expect(find.textContaining('stop receiving requests'), findsNothing);
    expect(
      find.textContaining(
        'may keep sending it notifications until you '
        'unpair it on the server',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });
}
