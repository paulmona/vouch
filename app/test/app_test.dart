import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vouch/app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: VouchApp()));
    await tester.pumpAndSettle();
  }

  testWidgets('home shows the not-paired empty state', (tester) async {
    await pumpApp(tester);
    expect(find.text('Not paired yet'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Pair with a server'), findsOne);
  });

  testWidgets('settings opens from the app bar', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('About'), findsOneWidget);
    // Not paired: only the Cloudflare token, for the coming pairing.
    expect(find.text('Cloudflare Access'), findsOneWidget);
    expect(find.text('Forget this server'), findsNothing);
  });

  testWidgets('pair button opens the pairing screen', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('Pair with a server'));
    await tester.pumpAndSettle();
    expect(find.text('Enter the link instead'), findsOneWidget);
  });

  testWidgets('home survives 200% text scaling without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: const ProviderScope(child: VouchApp()),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Not paired yet'), findsOneWidget);
  });
}
