import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vouch/app.dart';
import 'package:vouch/dev/sample_requests.dart';
import 'package:vouch/model/decision.dart';
import 'package:vouch/push/push_service.dart';
import 'package:vouch/screens/request/request_route_screen.dart';
import 'package:vouch/screens/request/request_screen.dart';
import 'package:vouch/theme/vouch_theme.dart';

/// a notification tap lands on the request, and a decision hands
/// the phone back instead of showing a confirmation page.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final t0 = DateTime.utc(2026, 11, 5, 13, 0);

  group('RequestScreen.onFinished', () {
    Future<List<DecisionOutcome>> run(
      WidgetTester tester,
      FakeDecider decider,
      String button,
    ) async {
      final finished = <DecisionOutcome>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: VouchTheme.light(),
          home: RequestScreen(
            request: SampleRequests.signIn(now: t0),
            onDecide: decider.call,
            onFinished: finished.add,
            now: () => t0,
          ),
        ),
      );
      await tester.tap(find.text(button));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      return finished;
    }

    testWidgets('fires for an approval', (tester) async {
      final f = await run(
        tester,
        FakeDecider(delay: Duration.zero),
        'Approve once',
      );
      expect(f.single, isA<Approved>());
    });

    testWidgets('fires for a denial', (tester) async {
      final f = await run(tester, FakeDecider(delay: Duration.zero), 'Deny');
      expect(f.single, isA<Denied>());
    });

    testWidgets('not for a cancelled fingerprint prompt', (tester) async {
      final f = await run(
        tester,
        FakeDecider(fixed: const Cancelled(), delay: Duration.zero),
        'Approve once',
      );
      expect(f, isEmpty);
      expect(find.text('Approve once'), findsOneWidget, reason: 'buttons back');
    });

    // Opened from a notification, the request waits for a tap on this
    // screen and carries no notice about the notification.
    testWidgets('opened from a notification: nothing decided without a tap', (
      tester,
    ) async {
      final decider = FakeDecider(delay: Duration.zero);
      await tester.pumpWidget(
        MaterialApp(
          theme: VouchTheme.light(),
          home: RequestScreen(
            request: SampleRequests.signIn(now: t0),
            onDecide: decider.call,
            now: () => t0,
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 2));
      expect(decider.decisions, isEmpty, reason: 'nothing without a tap');
      expect(find.textContaining('on the notification'), findsNothing);
    });

    testWidgets('a throwing decide shows the retry screen, not a spinner '
        'for good', (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: VouchTheme.light(),
          home: RequestScreen(
            request: SampleRequests.signIn(now: t0),
            onDecide: (_) async {
              calls++;
              throw StateError('Cannot use Ref after it has been disposed');
            },
            now: () => t0,
          ),
        ),
      );
      await tester.tap(find.text('Approve once'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(calls, 1);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('not for a failure (the retry screen stays)', (tester) async {
      final f = await run(
        tester,
        FakeDecider(fixed: const Failed('offline'), delay: Duration.zero),
        'Approve once',
      );
      expect(f, isEmpty);
    });
  });

  group('RequestRouteScreen', () {
    late List<MethodCall> platformCalls;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      platformCalls = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            platformCalls.add(call);
            return null;
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    Future<void> pumpRoute(
      WidgetTester tester, {
      required bool fromPush,
    }) async {
      // The route screen uses the wall clock for the countdown, so the
      // sample must still be pending now.
      final request = SampleRequests.signIn(
        remaining: const Duration(hours: 1),
      );
      final store = RequestStore()..put(request);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [requestStoreProvider.overrideWithValue(store)],
          child: MaterialApp(
            theme: VouchTheme.light(),
            home: RequestRouteScreen(
              requestId: request.requestId,
              fromPush: fromPush,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    // A release build has no fake decider: unpaired, a tap must not look
    // approved when nothing was sent.
    testWidgets('unpaired with no fallback decider: nothing looks decided', (
      tester,
    ) async {
      final request = SampleRequests.signIn(
        remaining: const Duration(hours: 1),
      );
      final store = RequestStore()..put(request);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            requestStoreProvider.overrideWithValue(store),
            unpairedDeciderProvider.overrideWithValue(null),
          ],
          child: MaterialApp(
            theme: VouchTheme.light(),
            home: RequestRouteScreen(
              requestId: request.requestId,
              fromPush: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Approve once'));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Approved'), findsNothing);
      expect(find.textContaining('not paired'), findsOneWidget);
      expect(
        platformCalls.map((c) => c.method),
        isNot(contains('SystemNavigator.pop')),
      );
    });

    testWidgets('from a notification: approve, then the activity finishes', (
      tester,
    ) async {
      await pumpRoute(tester, fromPush: true);
      await tester.tap(find.text('Approve once'));
      // FakeDecider's default delay.
      await tester.pump(const Duration(seconds: 1));
      expect(
        platformCalls.map((c) => c.method),
        contains('SystemNavigator.pop'),
      );
    });

    // A tap on the notification opens the request; Deny on the screen
    // decides, then the screen finishes.
    testWidgets('from a notification: deny, then the activity finishes', (
      tester,
    ) async {
      await pumpRoute(tester, fromPush: true);
      expect(find.text('Approve once'), findsOneWidget, reason: 'still open');
      expect(find.textContaining('on the notification'), findsNothing);
      expect(
        platformCalls.map((c) => c.method),
        isNot(contains('SystemNavigator.pop')),
      );

      await tester.tap(find.text('Deny'));
      await tester.pump(const Duration(seconds: 1));
      expect(
        platformCalls.map((c) => c.method),
        contains('SystemNavigator.pop'),
      );
    });

    testWidgets(
      'iOS, from a notification: approve, then back to Home',
      (tester) async {
        final request = SampleRequests.signIn(
          remaining: const Duration(hours: 1),
        );
        final store = RequestStore()..put(request);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [requestStoreProvider.overrideWithValue(store)],
            child: MaterialApp(
              theme: VouchTheme.light(),
              home: const Scaffold(body: Text('Home')),
            ),
          ),
        );
        // As the app does on a notification tap: the request on top of Home.
        unawaited(
          Navigator.of(tester.element(find.text('Home'))).push(
            MaterialPageRoute<void>(
              builder: (_) => RequestRouteScreen(
                requestId: request.requestId,
                fromPush: true,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Approve once'));
        await tester.pump(const Duration(seconds: 1));
        await tester.pumpAndSettle();
        expect(find.text('Approved'), findsNothing);
        expect(find.text('Home'), findsOneWidget);
        expect(
          platformCalls.map((c) => c.method),
          isNot(contains('SystemNavigator.pop')),
        );
      },
      variant: TargetPlatformVariant.only(TargetPlatform.iOS),
    );

    testWidgets('from Home: approve, no SystemNavigator.pop', (tester) async {
      await pumpRoute(tester, fromPush: false);
      await tester.tap(find.text('Approve once'));
      await tester.pump(const Duration(seconds: 1));
      expect(
        platformCalls.map((c) => c.method),
        isNot(contains('SystemNavigator.pop')),
      );
    });
  });

  test('request route carries the push origin', () {
    expect(Routes.request('r'), '/requests/r');
    expect(Routes.request('r', fromPush: true), '/requests/r?from=push');
  });

  testWidgets('started from a notification, the request is the first screen', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    PushService.instance.launchRequest = (requestId: 'req_0123456789');
    addTearDown(() => PushService.instance.launchRequest = null);
    await tester.pumpWidget(const ProviderScope(child: VouchApp()));
    await tester.pumpAndSettle();
    // Not paired and no such request locally: the request route's own
    // "no longer available" page, not Home.
    expect(find.text('This request is no longer available'), findsOneWidget);
    expect(find.text('Not paired yet'), findsNothing);
    expect(PushService.instance.takeLaunchRequest(), isNull, reason: 'taken');
  });
}
