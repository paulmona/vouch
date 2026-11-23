import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vouch/dev/sample_requests.dart';
import 'package:vouch/model/decision.dart';
import 'package:vouch/screens/request/request_screen.dart';
import 'package:vouch/theme/vouch_theme.dart';
import 'package:vouch_api/api.dart';

// A very long site name at a very large text size must not take the whole
// screen: its end, where the real domain is, stays readable and every button
// can still be reached.
void main() {
  // The app's own font, so lines break as they do on a phone (the default
  // test font draws every character a full em wide).
  setUpAll(() async {
    final inter = FontLoader('Inter');
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      inter.addFont(rootBundle.load('assets/fonts/Inter-$w.ttf'));
    }
    await inter.load();
  });

  final t0 = DateTime.utc(2026, 11, 4, 17, 40);

  // The longest host DNS allows, with a familiar name at the start and the
  // real domain at the end.
  final longHost = [
    'accounts.google.com',
    'a' * 63,
    'a' * 63,
    'a' * 63,
    'a' * 28,
    'evil.example',
  ].join('.');

  /// [shown] is [host], or an ellipsis and a tail of it that starts just
  /// after a dot.
  bool startsOnLabel(String shown, String host) {
    if (shown == host) return true;
    if (!shown.startsWith('\u2026')) return false;
    final kept = shown.substring(1);
    return host.endsWith(kept) && host[host.length - kept.length - 1] == '.';
  }

  ApprovalRequest withSite(ApprovalRequest r, String site) => ApprovalRequest(
    requestId: r.requestId,
    kind: r.kind,
    agent: r.agent,
    site: site,
    loginTitle: r.loginTitle,
    smsContact: r.smsContact,
    createdAt: r.createdAt,
    expiresAt: r.expiresAt,
    state: r.state,
  );

  Future<List<Decision>> pumpAt(
    WidgetTester tester,
    ApprovalRequest request, {
    required Size size,
    required double textScale,
  }) async {
    final decided = <Decision>[];
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: VouchTheme.light(),
        home: MediaQuery(
          data: MediaQueryData(
            size: size,
            textScaler: TextScaler.linear(textScale),
          ),
          child: RequestScreen(
            request: request,
            onDecide: (d) async {
              decided.add(d);
              return const Cancelled();
            },
            now: () => t0,
          ),
        ),
      ),
    );
    return decided;
  }

  final siteRow = find.byWidgetPredicate(
    (w) => w is Text && w.semanticsLabel != null,
  );

  for (final (name, size) in [
    ('portrait', const Size(320, 568)),
    ('landscape', const Size(568, 320)),
  ]) {
    testWidgets('a 253-character site at three times the text size keeps '
        'its end readable and every button reachable ($name)', (tester) async {
      expect(longHost.length, 253);
      final decided = await pumpAt(
        tester,
        withSite(SampleRequests.signIn(now: t0), longHost),
        size: size,
        textScale: 3,
      );
      expect(tester.takeException(), isNull);

      // At most three lines, the start given way to an ellipsis, the real
      // domain kept; a screen reader still gets the whole name.
      expect(siteRow, findsOneWidget);
      final row = tester.widget<Text>(siteRow);
      expect(row.maxLines, inInclusiveRange(1, 3));
      expect(row.data, startsWith('…'));
      expect(row.data, endsWith('evil.example'));
      expect(startsOnLabel(row.data!, longHost), isTrue, reason: row.data);
      expect(row.semanticsLabel, longHost);

      // In portrait it is in view as the screen opens; in landscape the
      // part above the buttons scrolls to it.
      if (size.height < size.width) {
        await tester.ensureVisible(siteRow);
        await tester.pumpAndSettle();
      }
      final rect = tester.getRect(siteRow);
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.bottom, lessThanOrEqualTo(size.height));

      // Deny can be reached and pressed.
      final deny = find.widgetWithText(OutlinedButton, 'Deny');
      await tester.ensureVisible(deny);
      await tester.pumpAndSettle();
      expect(tester.getRect(deny).bottom, lessThanOrEqualTo(size.height));
      await tester.tap(deny);
      await tester.pumpAndSettle();
      expect(decided, [Decision.deny]);
    });
  }

  // Wherever the cut falls, the kept end starts on a whole label, so it can
  // never read as a different domain ("evilyourbank.com" as "yourbank.com").
  final lookalike = [
    'accounts.google.com',
    'a' * 40,
    'evilyourbank.com',
  ].join('.');

  for (final size in [const Size(320, 568), const Size(568, 320)]) {
    for (final scale in [1.0, 1.5, 2.0, 2.5, 3.0, 4.0]) {
      testWidgets('a cut site starts on a whole label '
          '(${size.width.toInt()}x${size.height.toInt()}, ${scale}x)', (
        tester,
      ) async {
        await pumpAt(
          tester,
          withSite(SampleRequests.signIn(now: t0), lookalike),
          size: size,
          textScale: scale,
        );
        expect(tester.takeException(), isNull);
        final shown = tester.widget<Text>(siteRow).data!;
        expect(startsOnLabel(shown, lookalike), isTrue, reason: shown);
      });
    }
  }

  testWidgets('when even the last two labels do not fit, they are shown '
      'whole on more lines', (tester) async {
    final decided = await pumpAt(
      tester,
      withSite(SampleRequests.signIn(now: t0), lookalike),
      size: const Size(320, 240),
      textScale: 4,
    );
    expect(tester.takeException(), isNull);
    final row = tester.widget<Text>(siteRow);
    expect(row.data, '\u2026evilyourbank.com');
    expect(row.maxLines, isNull);
    final deny = find.widgetWithText(OutlinedButton, 'Deny');
    await tester.ensureVisible(deny);
    await tester.pumpAndSettle();
    await tester.tap(deny);
    await tester.pumpAndSettle();
    expect(decided, [Decision.deny]);
  });

  testWidgets('a site that fits is shown whole', (tester) async {
    await pumpAt(
      tester,
      SampleRequests.signIn(now: t0),
      size: const Size(320, 568),
      textScale: 3,
    );
    expect(tester.widget<Text>(siteRow).data, 'shop.example.com');
  });
}
