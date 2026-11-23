import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vouch/dev/sample_requests.dart';
import 'package:vouch/model/decision.dart';
import 'package:vouch/screens/request/request_screen.dart';
import 'package:vouch/theme/vouch_theme.dart';
import 'package:vouch_api/api.dart';

// Deny is on screen the moment a request opens, whatever the phone, the
// orientation, the text size or what the agent sent: no scrolling first.
void main() {
  // The app's own font, so lines break as they do on a phone.
  setUpAll(() async {
    final inter = FontLoader('Inter');
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      inter.addFont(rootBundle.load('assets/fonts/Inter-$w.ttf'));
    }
    await inter.load();
  });

  final t0 = DateTime.utc(2026, 11, 4, 17, 40);

  final longHost = [
    'accounts.google.com',
    'a' * 63,
    'a' * 63,
    'a' * 63,
    'a' * 28,
    'evil.example',
  ].join('.');

  ApprovalRequest signIn({String? site, String? agent}) {
    final r = SampleRequests.signIn(now: t0);
    return ApprovalRequest(
      requestId: r.requestId,
      kind: r.kind,
      agent: agent ?? r.agent,
      site: site ?? r.site,
      loginTitle: r.loginTitle,
      smsContact: r.smsContact,
      createdAt: r.createdAt,
      expiresAt: r.expiresAt,
      state: r.state,
    );
  }

  final requests = {
    'short site': signIn(),
    '253-character site': signIn(site: longHost),
    'long agent name': signIn(agent: 'Research agent ' * 12),
    'text request': SampleRequests.smsContact(now: t0),
  };

  // Logical sizes: a small phone and a large one, upright and on its side,
  // and a large phone upright in split screen.
  const sizes = {
    'small upright': Size(320, 568),
    'small on its side': Size(568, 320),
    'large upright': Size(384, 832),
    'large on its side': Size(832, 384),
    'large upright, split screen': Size(384, 400),
  };

  for (final MapEntry(key: what, value: request) in requests.entries) {
    for (final MapEntry(key: phone, value: size) in sizes.entries) {
      for (final scale in [1.0, 1.3, 2.0, 3.0, 3.5]) {
        testWidgets('Deny is in view without scrolling: $what, $phone, '
            '${scale}x text', (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final decided = <Decision>[];
          await tester.pumpWidget(
            MaterialApp(
              theme: VouchTheme.light(),
              home: MediaQuery(
                data: MediaQueryData(
                  size: size,
                  textScaler: TextScaler.linear(scale),
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
          expect(tester.takeException(), isNull);
          final deny = find.widgetWithText(OutlinedButton, 'Deny');
          final rect = tester.getRect(deny);
          expect(rect.top, greaterThanOrEqualTo(0), reason: '$rect');
          expect(rect.bottom, lessThanOrEqualTo(size.height), reason: '$rect');
          // Pressed where it stands, with no scroll in between.
          await tester.tap(deny);
          await tester.pumpAndSettle();
          expect(decided, [Decision.deny]);
        });
      }
    }
  }

  testWidgets('the parts that scroll show a scrollbar', (tester) async {
    const size = Size(568, 320);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: VouchTheme.light(),
        home: RequestScreen(
          request: signIn(site: longHost),
          onDecide: (d) async => const Cancelled(),
          now: () => t0,
        ),
      ),
    );
    final bars = tester.widgetList<Scrollbar>(find.byType(Scrollbar));
    expect(bars.length, 2);
    expect(bars.every((b) => b.thumbVisibility == true), isTrue);
  });
}
