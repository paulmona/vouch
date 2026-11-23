import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vouch/app.dart';
import 'package:vouch/theme/vouch_theme.dart';

void main() {
  testWidgets('pushing /pair?link=... opens the confirmation', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final router = buildRouter();
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(
          theme: VouchTheme.light(),
          routerConfig: router,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    const raw =
        'vouch://pair?v=1&server=http%3A%2F%2F10.0.0.20%3A8771&token=not-a-real-token-0000';
    unawaited(
      router.push('${Routes.pair}?link=${Uri.encodeQueryComponent(raw)}'),
    );
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Pair this phone with'), findsOneWidget);
    expect(find.text('10.0.0.20:8771'), findsOneWidget);
  });
}
