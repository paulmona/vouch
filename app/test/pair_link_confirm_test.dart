import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vouch/api/cloudflare_access.dart';
import 'package:vouch/pairing/pair_link.dart';
import 'package:vouch/pairing/paired_device.dart';
import 'package:vouch/screens/pair_screen.dart';
import 'package:vouch/theme/vouch_theme.dart';

void main() {
  final link = PairLink.parse(
    'vouch://pair?v=1&server=http%3A%2F%2F10.0.0.20%3A8771'
    '&token=not-a-real-token-0000',
  )!;

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Widget app(PairLink l) => ProviderScope(
    child: MaterialApp(
      theme: VouchTheme.light(),
      home: PairScreen(initialLink: l),
    ),
  );

  testWidgets('a handed-over link is shown for confirmation, not paired', (
    tester,
  ) async {
    await tester.pumpWidget(app(link));
    expect(find.text('Pair this phone with'), findsOneWidget);
    expect(find.text('10.0.0.20:8771'), findsOneWidget);
    expect(find.textContaining('Not encrypted'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Pair'), findsOneWidget);
    // Nothing has started: no progress step is shown.
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('Cancel returns to the scanner', (tester) async {
    await tester.pumpWidget(app(link));
    await tester.tap(find.widgetWithText(OutlinedButton, 'Cancel'));
    await tester.pump();
    expect(find.text('Enter the link instead'), findsOneWidget);
  });

  group('pasted links', () {
    Future<void> paste(WidgetTester tester, String server) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: VouchTheme.light(),
            home: const PairScreen(),
          ),
        ),
      );
      await tester.tap(find.text('Enter the link instead'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField),
        'vouch://pair?v=1&server=${Uri.encodeComponent(server)}'
        '&token=not-a-real-token-0000',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Pair'));
      await tester.pumpAndSettle();
    }

    testWidgets('plain HTTP on the LAN asks first, with the warning', (
      tester,
    ) async {
      await paste(tester, 'http://192.168.1.20:8771');
      expect(find.text('Pair this phone with'), findsOneWidget);
      expect(find.textContaining('Not encrypted'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    // With an Access token waiting, even an https link shows its host and
    // waits for a tap: the token goes only to a host the person saw.
    testWidgets('a waiting Access token: the host is confirmed first', (
      tester,
    ) async {
      await tester.runAsync(
        () => CloudflareAccessStore.instance.save(
          null,
          const AccessToken(clientId: 'abc.access', clientSecret: 's3cret'),
        ),
      );
      addTearDown(() => CloudflareAccessStore.instance.remove(null));
      await paste(tester, 'https://vouch.example.com');
      expect(find.text('Pair this phone with'), findsOneWidget);
      expect(find.text('vouch.example.com'), findsOneWidget);
      expect(
        find.textContaining(
          'Cloudflare Access service token to '
          'vouch.example.com',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('outside the app'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('plain HTTP to a public server is refused', (tester) async {
      await paste(tester, 'http://vouch.example.com');
      expect(find.text(PairLink.plainHttpRefused), findsOneWidget);
      expect(find.text('Pair this phone with'), findsNothing);
    });
  });

  testWidgets('an https link is not flagged as plain HTTP', (tester) async {
    final https = PairLink.parse(
      'vouch://pair?v=1&server=https%3A%2F%2Fvouch.example.com'
      '&token=not-a-real-token-0000',
    )!;
    await tester.pumpWidget(app(https));
    expect(find.text('vouch.example.com'), findsOneWidget);
    expect(find.textContaining('Not encrypted'), findsNothing);
  });

  // pairing replaces the keys before the server says yes, so a bad
  // link tapped on a paired phone broke the working pairing.
  testWidgets('a paired phone refuses the link and never offers Pair', (
    tester,
  ) async {
    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues({});
      await PairedDeviceStore().save(
        PairedDevice(
          deviceId: 'dev_0123456789',
          serverUrl: Uri.parse('https://vouch.example.com'),
          serverName: 'home-server',
          requireUserAuth: true,
          userAuthBound: 'attested',
          pairedAt: DateTime.utc(2026, 11, 15),
        ),
      );
    });
    await tester.pumpWidget(app(link));
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(find.text('Already paired with home-server'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Pair'), findsNothing);
  });
}
