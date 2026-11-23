import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vouch/alerts/alerts.dart';
import 'package:vouch/api/vouch_api_client.dart';
import 'package:vouch/model/decision.dart';
import 'package:vouch/push/alert_details.dart';
import 'package:vouch/requests/decision_service.dart';
import 'package:vouch/screens/request/request_screen.dart';
import 'package:vouch/text/shown_text.dart';
import 'package:vouch/theme/vouch_theme.dart';

// The app does not rely on the server refusing hidden characters. Agent,
// site, login title and alert text are shown as plain single-line text
// (an alert body may break lines), with anything hidden or out of place
// marked visibly.
void main() {
  const rlo = '\u202E'; // right-to-left override
  const zwsp = '\u200B'; // zero-width space

  group('ShownText', () {
    test('one line: bidi, zero-width and line breaks are marked', () {
      expect(ShownText.oneLine('Scout${rlo}moc.live'), 'Scout[U+202E]moc.live');
      expect(ShownText.oneLine('Sc${zwsp}out'), 'Sc[U+200B]out');
      expect(
        ShownText.oneLine('Scout\nApproved by Vouch'),
        'Scout[U+000A]Approved by Vouch',
      );
      expect(ShownText.oneLine('a\u2028b'), 'a[U+2028]b');
      expect(ShownText.oneLine('Hangul\u3164filler'), 'Hangul[U+3164]filler');
    });

    test('ordinary text is shown as is', () {
      expect(ShownText.oneLine('Research agent'), 'Research agent');
      expect(ShownText.oneLine('Café Zoë'), 'Café Zoë');
      expect(ShownText.host('shop.example.com'), 'shop.example.com');
      expect(ShownText.host('xn--bcher-kva.example'), 'xn--bcher-kva.example');
      expect(ShownText.host('2001:db8::1'), '2001:db8::1');
    });

    test('a host with a lookalike or any non-ASCII letter is marked', () {
      // Cyrillic a (U+0430) in place of the Latin one.
      expect(ShownText.host('ex\u0430mple.com'), 'ex[U+0430]mple.com');
      expect(ShownText.host('shop.example.com '), 'shop.example.com[U+0020]');
    });

    test('alert body keeps line breaks and marks the rest', () {
      expect(ShownText.lines('line one\nline two'), 'line one\nline two');
      expect(ShownText.lines('a\rb${rlo}c'), 'a[U+000D]b[U+202E]c');
    });

    test('blank text is shown as blank, not as nothing', () {
      expect(ShownText.oneLine(''), ShownText.blank);
      expect(ShownText.oneLine('   '), ShownText.blank);
    });

    // Mirrors the server: a code point Unicode has not assigned may render
    // as anything a later font decides, so it is marked.
    test('an unassigned code point is marked', () {
      expect(ShownText.oneLine('Sc\u0378out'), 'Sc[U+0378]out');
      expect(ShownText.lines('a\u0378\nb'), 'a[U+0378]\nb');
      expect(ShownText.oneLine('\u0378'), '[U+0378]');
    });

    // A value made only of characters that draw nothing on their own
    // (ignorables, combining marks, spaces, private use) reads as empty.
    test('a value with nothing visible is shown as blank', () {
      for (final s in [
        '\u034F',
        '\uFE0F',
        '\u0301',
        '\uE000',
        ' \u0301 ',
        '\t\u0301',
      ]) {
        expect(
          ShownText.oneLine(s),
          ShownText.blank,
          reason: s.runes.toString(),
        );
        expect(ShownText.lines(s), ShownText.blank, reason: s.runes.toString());
      }
    });

    // A private-use character draws whatever a font puts there, so beside
    // visible text it is marked like any other hidden character.
    test('a private-use character beside text is marked', () {
      expect(ShownText.oneLine('Pay\uE000Pal'), 'Pay[U+E000]Pal');
      expect(ShownText.lines('Pay\uE000Pal\nok'), 'Pay[U+E000]Pal\nok');
      expect(ShownText.oneLine('a\u{F0000}b'), 'a[U+F0000]b');
    });

    test('a null notehead or object replacement beside text is marked', () {
      expect(ShownText.oneLine('Pay\u{1D159}Pal'), 'Pay[U+1D159]Pal');
      expect(ShownText.oneLine('Pay\uFFFCPal'), 'Pay[U+FFFC]Pal');
      expect(ShownText.lines('Pay\uFFFCPal\nok'), 'Pay[U+FFFC]Pal\nok');
      expect(ShownText.lines('a\u{1D159}b'), 'a[U+1D159]b');
    });

    test('a null notehead or object replacement alone is blank', () {
      for (final s in ['\u{1D159}', '\uFFFC', ' \uFFFC\u{1D159} ']) {
        expect(
          ShownText.oneLine(s),
          ShownText.blank,
          reason: s.runes.toString(),
        );
        expect(ShownText.lines(s), ShownText.blank, reason: s.runes.toString());
      }
    });

    test(
      'combining marks and emoji with a variation selector show normally',
      () {
        expect(ShownText.oneLine('Cafe\u0301'), 'Cafe\u0301');
        expect(ShownText.oneLine('Zo\u00EB'), 'Zo\u00EB');
        expect(ShownText.oneLine('\u2764\uFE0F'), '\u2764\uFE0F');
        expect(ShownText.oneLine('Scout \u2764\uFE0F'), 'Scout \u2764\uFE0F');
      },
    );
  });

  final t0 = DateTime.utc(2026, 11, 18, 12);
  final hostile = ApprovalRequest(
    requestId: '3f9c2a7b1d4e8f60',
    kind: ApprovalRequestKindEnum.signIn,
    agent: 'Scout${rlo}lepyap',
    site: 'ex\u0430mple.com',
    loginTitle: 'Example\nApproved already',
    createdAt: t0,
    expiresAt: t0.add(const Duration(minutes: 5)),
    state: ApprovalRequestStateEnum.pending,
  );

  testWidgets('the request screen marks hidden characters in what it shows', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: VouchTheme.light(),
        home: RequestScreen(
          request: hostile,
          onDecide: (_) async => const Cancelled(),
          now: () => t0,
        ),
      ),
    );
    final shown = tester
        .widgetList<RichText>(find.byType(RichText))
        .map((w) => w.text.toPlainText())
        .join('\n');
    expect(shown, contains('Scout[U+202E]lepyap'));
    expect(shown, contains('ex[U+0430]mple.com'));
    expect(shown, contains('Example[U+000A]Approved already'));
    expect(shown, isNot(contains(rlo)));
    expect(shown, isNot(contains('\u0430')));
    expect(shown, isNot(contains('Example\nApproved')));
  });

  test('the fingerprint prompt marks them too', () {
    final p = DecisionService.promptFor(hostile, Decision.once);
    expect(p.subtitle, 'ex[U+0430]mple.com, asked by Scout[U+202E]lepyap');
  });

  test('alert text in a notification and on screen is marked', () {
    final a = Alert(
      alertId: 'alr_0123456789',
      severity: AlertSeverityEnum.critical,
      title: 'Disk${zwsp}full',
      body: 'line one\nline two$rlo',
      createdAt: t0,
    );
    final n = AlertDetails.textFor(a);
    expect(n.title, 'Critical: Disk[U+200B]full');
    expect(n.body, 'line one\nline two[U+202E]');
    expect(a.shownTitle, 'Disk[U+200B]full');
  });
}
