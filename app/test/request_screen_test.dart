import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vouch/dev/sample_requests.dart';
import 'package:vouch/model/decision.dart';
import 'package:vouch/screens/request/countdown.dart';
import 'package:vouch/screens/request/request_screen.dart';
import 'package:vouch/theme/vouch_theme.dart';
import 'package:vouch_api/api.dart';

void main() {
  final t0 = DateTime.utc(2026, 11, 4, 17, 40);

  Widget wrap(Widget child, {ThemeData? theme, double textScale = 1}) {
    return MaterialApp(
      theme: theme ?? VouchTheme.light(),
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: child,
      ),
    );
  }

  group('pending sign-in', () {
    ApprovalRequest settled(ApprovalRequest r) => ApprovalRequest(
      requestId: r.requestId,
      kind: r.kind,
      agent: r.agent,
      site: r.site,
      loginTitle: r.loginTitle,
      createdAt: r.createdAt,
      expiresAt: r.expiresAt,
      state: ApprovalRequestStateEnum.deny,
      decidedBy: ApprovalRequestDecidedByEnum.otherDevice,
    );

    testWidgets('settled elsewhere while on screen -> Answered on another '
        'device, buttons gone', (tester) async {
      final r = SampleRequests.signIn(now: t0);
      final decider = FakeDecider();
      await tester.pumpWidget(
        wrap(RequestScreen(request: r, onDecide: decider.call, now: () => t0)),
      );
      await tester.pumpWidget(
        wrap(
          RequestScreen(
            request: settled(r),
            onDecide: decider.call,
            now: () => t0,
          ),
        ),
      );
      expect(find.text('Answered on another device'), findsOneWidget);
      expect(find.text('Deny'), findsNothing);
    });

    testWidgets('a decision already on its way is not interrupted', (
      tester,
    ) async {
      final r = SampleRequests.signIn(now: t0);
      final decider = FakeDecider(delay: const Duration(milliseconds: 300));
      await tester.pumpWidget(
        wrap(RequestScreen(request: r, onDecide: decider.call, now: () => t0)),
      );
      await tester.tap(find.text('Deny'));
      await tester.pump();
      await tester.pumpWidget(
        wrap(
          RequestScreen(
            request: settled(r),
            onDecide: decider.call,
            now: () => t0,
          ),
        ),
      );
      await tester.pumpAndSettle();
      // Its own outcome, not the other device's.
      expect(find.text('Denied'), findsOneWidget);
      expect(find.text('Answered on another device'), findsNothing);
    });

    testWidgets('says who, what and where, with the login and countdown', (
      tester,
    ) async {
      final decider = FakeDecider();
      await tester.pumpWidget(
        wrap(
          RequestScreen(
            request: SampleRequests.signIn(now: t0),
            onDecide: decider.call,
            now: () => t0,
          ),
        ),
      );
      expect(find.text('Approval request'), findsOneWidget);
      expect(
        find.textContaining('would like approval to sign in to'),
        findsOneWidget,
      );
      expect(find.textContaining('Scout'), findsWidgets);
      expect(find.textContaining('shop.example.com'), findsWidgets);
      expect(find.text('Example'), findsOneWidget);
      expect(find.text('Expires in 4:32'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Approve once'), findsOne);
      expect(find.widgetWithText(FilledButton, 'Always allow'), findsOne);
      expect(find.widgetWithText(OutlinedButton, 'Deny'), findsOne);
    });

    testWidgets('approve once -> Approved, and the decision is passed on', (
      tester,
    ) async {
      final decider = FakeDecider(delay: const Duration(milliseconds: 300));
      await tester.pumpWidget(
        wrap(
          RequestScreen(
            request: SampleRequests.signIn(now: t0),
            onDecide: decider.call,
            now: () => t0,
          ),
        ),
      );
      await tester.tap(find.text('Approve once'));
      await tester.pump();
      // While in flight every button is disabled and a spinner shows.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      final deny = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Deny'),
      );
      expect(deny.onPressed, isNull);

      await tester.pump(const Duration(milliseconds: 400));
      expect(decider.decisions, [Decision.once]);
      expect(find.text('Approved'), findsOneWidget);
      expect(find.text('Scout can sign in to shop.example.com now.'), findsOne);
      expect(find.widgetWithText(FilledButton, 'Done'), findsOneWidget);
    });

    testWidgets('always allow -> Always allowed with the revoke hint', (
      tester,
    ) async {
      final decider = FakeDecider(delay: Duration.zero);
      await tester.pumpWidget(
        wrap(
          RequestScreen(
            request: SampleRequests.signIn(now: t0),
            onDecide: decider.call,
            now: () => t0,
          ),
        ),
      );
      await tester.tap(find.text('Always allow'));
      await tester.pump(const Duration(milliseconds: 10));
      expect(decider.decisions, [Decision.always]);
      expect(find.text('Always allowed'), findsOneWidget);
      expect(
        find.textContaining('To stop this, ask the agent to revoke it.'),
        findsOneWidget,
      );
    });

    testWidgets('deny -> Denied', (tester) async {
      final decider = FakeDecider(delay: Duration.zero);
      await tester.pumpWidget(
        wrap(
          RequestScreen(
            request: SampleRequests.signIn(now: t0),
            onDecide: decider.call,
            now: () => t0,
          ),
        ),
      );
      await tester.tap(find.text('Deny'));
      await tester.pump(const Duration(milliseconds: 10));
      expect(decider.decisions, [Decision.deny]);
      expect(find.text('Denied'), findsOneWidget);
    });

    testWidgets('a cancelled fingerprint prompt brings the buttons back', (
      tester,
    ) async {
      final decider = FakeDecider(
        fixed: const Cancelled(),
        delay: Duration.zero,
      );
      await tester.pumpWidget(
        wrap(
          RequestScreen(
            request: SampleRequests.signIn(now: t0),
            onDecide: decider.call,
            now: () => t0,
          ),
        ),
      );
      await tester.tap(find.text('Approve once'));
      await tester.pump(const Duration(milliseconds: 10));
      expect(find.text('Approve once'), findsOneWidget);
      expect(find.text('Approved'), findsNothing);
      expect(find.text('Not confirmed'), findsNothing);
      final approve = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Approve once'),
      );
      expect(approve.onPressed, isNotNull);
    });

    testWidgets('a changed request comes back to review, with a notice', (
      tester,
    ) async {
      final r = SampleRequests.signIn(now: t0);
      final decider = FakeDecider(fixed: ShownChanged(r), delay: Duration.zero);
      await tester.pumpWidget(
        wrap(RequestScreen(request: r, onDecide: decider.call, now: () => t0)),
      );
      expect(find.text('This request changed. Review it again.'), findsNothing);
      await tester.tap(find.text('Approve once'));
      await tester.pump(const Duration(milliseconds: 10));
      expect(
        find.text('This request changed. Review it again.'),
        findsOneWidget,
      );
      expect(find.text('Approved'), findsNothing);
      final approve = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Approve once'),
      );
      expect(approve.onPressed, isNotNull);
    });

    testWidgets(
      'a failed send offers Try again, which returns to the buttons',
      (tester) async {
        final decider = FakeDecider(
          fixed: const Failed('No connection.'),
          delay: Duration.zero,
        );
        await tester.pumpWidget(
          wrap(
            RequestScreen(
              request: SampleRequests.signIn(now: t0),
              onDecide: decider.call,
              now: () => t0,
            ),
          ),
        );
        await tester.tap(find.text('Deny'));
        await tester.pump(const Duration(milliseconds: 10));
        expect(find.text("Couldn't send your decision"), findsOneWidget);
        expect(find.text('No connection.'), findsOneWidget);
        await tester.tap(find.text('Try again'));
        await tester.pump();
        expect(find.text('Approve once'), findsOneWidget);
      },
    );

    testWidgets('409 already decided -> Answered on another device', (
      tester,
    ) async {
      final decider = FakeDecider(
        fixed: const AnsweredElsewhere(),
        delay: Duration.zero,
      );
      await tester.pumpWidget(
        wrap(
          RequestScreen(
            request: SampleRequests.signIn(now: t0),
            onDecide: decider.call,
            now: () => t0,
          ),
        ),
      );
      await tester.tap(find.text('Approve once'));
      await tester.pump(const Duration(milliseconds: 10));
      expect(find.text('Answered on another device'), findsOneWidget);
    });
  });

  group('countdown', () {
    testWidgets('ticks down and expires on its own', (tester) async {
      var now = t0;
      final decider = FakeDecider();
      await tester.pumpWidget(
        wrap(
          RequestScreen(
            request: SampleRequests.signIn(
              now: t0,
              remaining: const Duration(seconds: 35),
            ),
            onDecide: decider.call,
            now: () => now,
          ),
        ),
      );
      expect(find.text('Expires in 0:35'), findsOneWidget);

      now = t0.add(const Duration(seconds: 10));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Expires in 0:25'), findsOneWidget);
      final countdown = tester.widget<Countdown>(find.byType(Countdown));
      expect(countdown.remaining <= Countdown.urgent, isTrue);

      now = t0.add(const Duration(seconds: 36));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Request expired'), findsOneWidget);
      expect(find.text('Approve once'), findsNothing);
      expect(decider.decisions, isEmpty);
    });

    test('formats m:ss', () {
      expect(Countdown.format(const Duration(minutes: 4, seconds: 5)), '4:05');
      expect(Countdown.format(Duration.zero), '0:00');
      expect(Countdown.format(const Duration(seconds: 59)), '0:59');
    });
  });

  group('sms_contact', () {
    testWidgets('names the agent, the person, number and reason; no Always', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          RequestScreen(
            request: SampleRequests.smsContact(now: t0),
            onDecide: FakeDecider().call,
            now: () => t0,
          ),
        ),
      );
      // The agent's name stands on its own (held to two lines), the rest
      // of the sentence follows.
      expect(find.text('Ava'), findsOneWidget);
      expect(
        find.textContaining('would like approval to text (204) 555-0150'),
        findsOneWidget,
      );
      expect(find.text('(204) 555-0150'), findsOneWidget);
      // The agent's words, quoted and attributed.
      expect(find.text('Reason given by Ava'), findsOneWidget);
      expect(
        find.text(
          '\u201CThe owner asked me to confirm Tuesday\'s dinner with Sam.\u201D',
        ),
        findsOneWidget,
      );
      expect(find.text('Always allow'), findsNothing);
      // Approving permits Sam until removed: not "once".
      expect(find.text('Approve once'), findsNothing);
      expect(find.text('Approve'), findsOneWidget);
      expect(find.text('Deny'), findsOneWidget);
      expect(
        requestHeadline(SampleRequests.smsContact(now: t0)),
        'Ava would like approval to text (204) 555-0150',
      );
    });

    testWidgets('a contact name that looks like a number: the headline '
        'names the real number and the name is labelled as the agent\'s', (
      tester,
    ) async {
      final r = SampleRequests.smsContact(now: t0);
      final spoof = ApprovalRequest(
        requestId: r.requestId,
        kind: r.kind,
        agent: r.agent,
        site: '+19005550123',
        loginTitle: null,
        smsContact: ApprovalRequestSmsContact(
          phone: '+19005550123',
          name: '+1 (416) 555-0199',
          reason: r.smsContact!.reason,
        ),
        createdAt: r.createdAt,
        expiresAt: r.expiresAt,
        state: r.state,
      );
      await tester.pumpWidget(
        wrap(
          RequestScreen(
            request: spoof,
            onDecide: FakeDecider().call,
            now: () => t0,
          ),
        ),
      );
      expect(
        requestHeadline(spoof),
        'Ava would like approval to text (900) 555-0123',
      );
      expect(
        find.textContaining('would like approval to text (900) 555-0123'),
        findsOneWidget,
      );
      expect(find.textContaining('416'), findsOneWidget);
      expect(find.text('+1 (416) 555-0199'), findsOneWidget);
      expect(find.text('Name given by Ava'), findsOneWidget);
    });

    testWidgets('approve -> Ava can text the number, and how to stop it', (
      tester,
    ) async {
      final decider = FakeDecider(delay: const Duration(milliseconds: 300));
      await tester.pumpWidget(
        wrap(
          RequestScreen(
            request: SampleRequests.smsContact(now: t0),
            onDecide: decider.call,
            now: () => t0,
          ),
        ),
      );
      await tester.tap(find.text('Approve'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(decider.decisions, [Decision.once]);
      expect(
        find.textContaining('Ava can text (204) 555-0150 now.'),
        findsOneWidget,
      );
      expect(find.textContaining('Permitted contacts'), findsOneWidget);
      expect(find.text('(204) 555-0150'), findsOneWidget);
    });
  });

  group('opened in a final state', () {
    testWidgets('approved by this device', (tester) async {
      await tester.pumpWidget(
        wrap(
          RequestScreen(
            request: SampleRequests.signIn(
              now: t0,
              state: ApprovalRequestStateEnum.once,
              decidedBy: ApprovalRequestDecidedByEnum.thisDevice,
            ),
            onDecide: FakeDecider().call,
            now: () => t0,
          ),
        ),
      );
      expect(find.text('Approved'), findsOneWidget);
      expect(find.text('Approve once'), findsNothing);
    });

    testWidgets('approved by another device', (tester) async {
      await tester.pumpWidget(
        wrap(
          RequestScreen(
            request: SampleRequests.signIn(
              now: t0,
              state: ApprovalRequestStateEnum.always,
              decidedBy: ApprovalRequestDecidedByEnum.otherDevice,
            ),
            onDecide: FakeDecider().call,
            now: () => t0,
          ),
        ),
      );
      expect(find.text('Answered on another device'), findsOneWidget);
    });

    testWidgets('timed out', (tester) async {
      await tester.pumpWidget(
        wrap(
          RequestScreen(
            request: SampleRequests.signIn(
              now: t0,
              state: ApprovalRequestStateEnum.timeout,
            ),
            onDecide: FakeDecider().call,
            now: () => t0,
          ),
        ),
      );
      expect(find.text('Request expired'), findsOneWidget);
    });

    // A sign-in lasts minutes, a request to text someone new lasts hours:
    // the expired page says neither.
    testWidgets('timed out text request: the page claims no time', (
      tester,
    ) async {
      final r = SampleRequests.smsContact(now: t0);
      await tester.pumpWidget(
        wrap(
          RequestScreen(
            request: ApprovalRequest(
              requestId: r.requestId,
              kind: r.kind,
              agent: r.agent,
              site: r.site,
              loginTitle: r.loginTitle,
              smsContact: r.smsContact,
              createdAt: r.createdAt,
              expiresAt: r.expiresAt,
              state: ApprovalRequestStateEnum.timeout,
            ),
            onDecide: FakeDecider().call,
            now: () => t0,
          ),
        ),
      );
      expect(find.text('Request expired'), findsOneWidget);
      expect(
        find.text('Nobody answered in time, so it was denied.'),
        findsOneWidget,
      );
      expect(find.textContaining('minute'), findsNothing);
    });

    testWidgets('withdrawn by the agent', (tester) async {
      await tester.pumpWidget(
        wrap(
          RequestScreen(
            request: SampleRequests.signIn(
              now: t0,
              state: ApprovalRequestStateEnum.cancelled,
            ),
            onDecide: FakeDecider().call,
            now: () => t0,
          ),
        ),
      );
      expect(find.text('Request withdrawn'), findsOneWidget);
    });
  });

  group('accessibility and scaling', () {
    // Large phone: 1440x3120 physical, ~3.5 dpr -> 411x891 logical.
    // Small phone: 360x640 logical.
    for (final (name, size, dpr) in [
      ('large phone', const Size(1440, 3120), 3.5),
      ('small phone', const Size(1080, 1920), 3.0),
    ]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('$name at ${scale}x text: no overflow, buttons reachable', (
          tester,
        ) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = dpr;
          addTearDown(tester.view.reset);
          await tester.pumpWidget(
            wrap(
              RequestScreen(
                request: SampleRequests.signIn(now: t0),
                onDecide: FakeDecider().call,
                now: () => t0,
              ),
              textScale: scale,
            ),
          );
          expect(tester.takeException(), isNull);
          // All three buttons are on screen without scrolling.
          final screen = tester.getRect(find.byType(RequestScreen));
          for (final label in ['Approve once', 'Always allow', 'Deny']) {
            final rect = tester.getRect(find.text(label));
            expect(screen.contains(rect.topLeft), isTrue, reason: label);
            expect(screen.contains(rect.bottomRight), isTrue, reason: label);
          }
        });
      }
    }

    for (final (name, theme) in [
      ('light', VouchTheme.light()),
      ('dark', VouchTheme.dark()),
    ]) {
      testWidgets('$name theme meets tap-target and contrast guidelines', (
        tester,
      ) async {
        final handle = tester.ensureSemantics();
        await tester.pumpWidget(
          wrap(
            RequestScreen(
              request: SampleRequests.signIn(now: t0),
              onDecide: FakeDecider().call,
              now: () => t0,
            ),
            theme: theme,
          ),
        );
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        handle.dispose();
      });
    }
  });

  test('requestHeadline', () {
    expect(
      requestHeadline(SampleRequests.signIn(now: t0)),
      'Scout would like approval to sign in to shop.example.com',
    );
  });
}
