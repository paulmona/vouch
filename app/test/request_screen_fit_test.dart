import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vouch/dev/sample_requests.dart';
import 'package:vouch/screens/request/request_screen.dart';
import 'package:vouch/theme/vouch_theme.dart';
import 'package:vouch_api/api.dart';

// A long agent name on a small phone with large text must not push the site
// out of view while the buttons can still be pressed.
void main() {
  final t0 = DateTime.utc(2026, 11, 4, 17, 40);
  // 64 characters, the longest name the contract allows.
  const longAgent =
      'Research assistant for the quarterly planning and budget reviews';

  ApprovalRequest withAgent(ApprovalRequest r, String agent) => ApprovalRequest(
    requestId: r.requestId,
    kind: r.kind,
    agent: agent,
    site: r.site,
    loginTitle: r.loginTitle,
    smsContact: r.smsContact,
    createdAt: r.createdAt,
    expiresAt: r.expiresAt,
    state: r.state,
  );

  Future<void> pumpSmall(WidgetTester tester, ApprovalRequest request) async {
    // A small phone (320 x 568 dp) at twice the normal text size.
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: VouchTheme.light(),
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 568),
            textScaler: TextScaler.linear(2),
          ),
          child: RequestScreen(
            request: request,
            onDecide: FakeDecider().call,
            now: () => t0,
          ),
        ),
      ),
    );
  }

  /// [target] is drawn in full on screen, above the first button.
  void expectVisibleAboveButtons(WidgetTester tester, Finder target) {
    expect(target, findsOneWidget);
    final rect = tester.getRect(target);
    final firstButton = tester.getRect(find.byType(FilledButton).first);
    expect(rect.top, greaterThanOrEqualTo(0));
    expect(rect.bottom, lessThanOrEqualTo(firstButton.top));
    // And every button is itself on screen.
    for (final b in tester.widgetList(find.byType(ButtonStyleButton))) {
      expect(tester.getRect(find.byWidget(b)).bottom, lessThanOrEqualTo(568));
    }
  }

  testWidgets('the site sits in its own labelled row above the buttons', (
    tester,
  ) async {
    await pumpSmall(
      tester,
      withAgent(SampleRequests.signIn(now: t0), longAgent),
    );
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Approve once'),
          )
          .onPressed,
      isNotNull,
    );
    expectVisibleAboveButtons(tester, find.text('Site'));
    expectVisibleAboveButtons(tester, find.text('shop.example.com'));
  });

  testWidgets('the contact sits in its own labelled row above the buttons', (
    tester,
  ) async {
    await pumpSmall(
      tester,
      withAgent(SampleRequests.smsContact(now: t0), longAgent),
    );
    expectVisibleAboveButtons(tester, find.text('Text to'));
    expectVisibleAboveButtons(tester, find.text('(204) 555-0150'));
  });

  ApprovalRequest smsWith({required String name, required String phone}) {
    final r = SampleRequests.smsContact(now: t0);
    return ApprovalRequest(
      requestId: r.requestId,
      kind: r.kind,
      agent: r.agent,
      site: phone,
      loginTitle: r.loginTitle,
      smsContact: ApprovalRequestSmsContact(
        phone: phone,
        name: name,
        reason: r.smsContact!.reason,
      ),
      createdAt: r.createdAt,
      expiresAt: r.expiresAt,
      state: r.state,
    );
  }

  // The agent chooses the contact's name; the number is what gets texted.
  testWidgets('a text request shows the number above the buttons, the name '
      'second on one line', (tester) async {
    await pumpSmall(tester, smsWith(name: longAgent, phone: '+12045550150'));
    expectVisibleAboveButtons(tester, find.text('(204) 555-0150'));
    final name = tester.widget<Text>(find.text(longAgent));
    expect(name.maxLines, 1);
    expect(name.overflow, TextOverflow.ellipsis);
    expect(
      tester.getTopLeft(find.text('(204) 555-0150')).dy,
      lessThan(tester.getTopLeft(find.text(longAgent)).dy),
    );
  });

  testWidgets('hidden characters in the number are marked', (tester) async {
    await pumpSmall(tester, smsWith(name: 'Sam', phone: '+1204555\u202E0150'));
    expectVisibleAboveButtons(tester, find.text('+1204555[U+202E]0150'));
  });

  testWidgets('the agent name is held to two lines', (tester) async {
    await pumpSmall(
      tester,
      withAgent(SampleRequests.signIn(now: t0), longAgent),
    );
    final name = tester.widget<Text>(find.text(longAgent));
    expect(name.maxLines, 2);
    expect(name.overflow, TextOverflow.ellipsis);
  });
}
