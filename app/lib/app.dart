import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'alerts/alerts.dart';
import 'dev/key_self_test_screen.dart';
import 'dev/request_preview_screen.dart';
import 'pairing/device_session.dart';
import 'pairing/pair_link.dart';
import 'pairing/pair_link_channel.dart';
import 'push/check_in.dart';
import 'push/push_event.dart';
import 'push/push_service.dart';
import 'push/push_token_sync.dart';
import 'requests/request_providers.dart';

import 'screens/about_screen.dart';
import 'screens/alerts_screen.dart';
import 'screens/cloudflare_access_screen.dart';
import 'screens/home_screen.dart';
import 'screens/notification_health_screen.dart';
import 'screens/pair_screen.dart';
import 'screens/request/request_route_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/sms/contacts_screen.dart';
import 'screens/sms/thread_screen.dart';
import 'server/modules.dart';
import 'sms/sms_providers.dart';
import 'theme/vouch_theme.dart';

/// Route paths.
abstract final class Routes {
  static const home = '/';
  static const pair = '/pair';
  static const settings = '/settings';
  static const about = '/settings/about';
  static const notificationHealth = '/settings/notifications';

  /// Recent alerts; [focus] is the one a notification was about.
  static String alerts({String? focus}) => focus == null
      ? '/alerts'
      : '/alerts?id=${Uri.encodeQueryComponent(focus)}';

  /// [fromPush]: opened from a notification, so after a decision the app
  /// steps out of the way instead of going back to Home.
  static String request(String id, {bool fromPush = false}) =>
      fromPush ? '/requests/$id?from=push' : '/requests/$id';

  /// The Cloudflare Access service token for [server], or for the
  /// next pairing when null.
  static String cloudflareAccess([Uri? server]) => server == null
      ? '/cloudflare-access'
      : '/cloudflare-access?server=${Uri.encodeQueryComponent('$server')}';

  /// Who the agent may text.
  static const smsContacts = '/sms-contacts';

  /// One SMS conversation; [name] is the contact's, when known.
  static String smsThread(String e164, {String? name}) {
    final path = '/sms/${Uri.encodeComponent(e164)}';
    return name == null ? path : '$path?name=${Uri.encodeQueryComponent(name)}';
  }

  /// Debug builds only.
  static const requestPreview = '/settings/dev/request-preview';
  static const keySelfTest = '/settings/dev/key-self-test';
}

GoRouter buildRouter() => GoRouter(
  routes: [
    GoRoute(
      path: Routes.home,
      builder: (context, state) => const HomeScreen(),
      routes: [
        GoRoute(
          path: 'pair',
          builder: (context, state) => PairScreen(
            initialLink: switch (state.uri.queryParameters['link']) {
              final raw? => PairLink.parse(raw),
              null => null,
            },
          ),
        ),
        GoRoute(
          path: 'requests/:id',
          builder: (context, state) => RequestRouteScreen(
            requestId: state.pathParameters['id']!,
            fromPush: state.uri.queryParameters['from'] == 'push',
          ),
        ),
        GoRoute(
          path: 'alerts',
          builder: (context, state) =>
              AlertsScreen(focus: state.uri.queryParameters['id']),
        ),
        GoRoute(
          path: 'cloudflare-access',
          builder: (context, state) => CloudflareAccessScreen(
            server: switch (state.uri.queryParameters['server']) {
              final s? => Uri.tryParse(s),
              null => null,
            },
          ),
        ),
        GoRoute(
          path: 'sms-contacts',
          builder: (context, state) => const ContactsScreen(),
        ),
        GoRoute(
          path: 'sms/:phone',
          builder: (context, state) => ThreadScreen(
            phone: state.pathParameters['phone']!,
            name: state.uri.queryParameters['name'],
          ),
        ),
        GoRoute(
          path: 'settings',
          builder: (context, state) => const SettingsScreen(),
          routes: [
            GoRoute(
              path: 'notifications',
              builder: (context, state) => const NotificationHealthScreen(),
            ),
            GoRoute(
              path: 'about',
              builder: (context, state) => const AboutScreen(),
            ),
            if (kDebugMode) ...[
              GoRoute(
                path: 'dev/request-preview',
                builder: (context, state) => const RequestPreviewScreen(),
              ),
              GoRoute(
                path: 'dev/key-self-test',
                builder: (context, state) => const KeySelfTestScreen(),
              ),
            ],
          ],
        ),
      ],
    ),
  ],
);

class VouchApp extends ConsumerStatefulWidget {
  const VouchApp({super.key});

  @override
  ConsumerState<VouchApp> createState() => _VouchAppState();
}

class _VouchAppState extends ConsumerState<VouchApp>
    with WidgetsBindingObserver {
  late final GoRouter _router = buildRouter();
  StreamSubscription<RequestOpen>? _openRequest;
  StreamSubscription<String>? _openAlert;
  StreamSubscription<PushEvent>? _pushEvents;
  final _pairLinks = PairLinkChannel();
  StreamSubscription<String>? _pairLinkSub;
  Timer? _foregroundPoll;

  /// How often the open app asks the server for pending requests on its
  /// own. A missed or delayed push (iOS delivers data pushes at its own
  /// discretion) must not mean staring at an empty Home while a 5-minute
  /// request runs out. One small signed GET; only while on screen.
  static const foregroundPollEvery = Duration(seconds: 20);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startForegroundPoll();
    // A tapped request notification opens that request.
    _openRequest = PushService.instance.openRequest.stream.listen(
      _openFromPush,
    );
    // Started from a notification: the request is the first screen, not
    // Home with the request somewhere in a list.
    final launch = PushService.instance.takeLaunchRequest();
    if (launch != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _openFromPush(launch),
      );
    }
    _openAlert = PushService.instance.openAlert.stream.listen(_showAlert);
    final launchAlert = PushService.instance.takeLaunchAlert();
    if (launchAlert != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _showAlert(launchAlert),
      );
    }
    // A request (or clear) push while the app is on screen: the Home list
    // refreshes on its own, so the request is there without a pull-down.
    _pushEvents = PushService.instance.events.stream.listen(_onPushEvent);
    // Firebase token rotation -> PUT /v1/devices/me/push-token while paired.
    ref.read(pushTokenSyncProvider);
    // A vouch://pair link handed over by Android opens the pair screen,
    // which asks before pairing.
    _pairLinkSub = _pairLinks.links.listen(_openPairLink);
    // After the first frame, like the launch request above: a push before
    // the router has taken its initial location sometimes ended with Home
    // on top of the pair screen.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => unawaited(
        _pairLinks.initialLink().then((l) {
          if (l != null && mounted) _openPairLink(l);
        }),
      ),
    );
  }

  void _openFromPush(RequestOpen open) =>
      _router.push(Routes.request(open.requestId, fromPush: true));

  void _showAlert(String id) => _router.push(Routes.alerts(focus: id));

  void _onPushEvent(PushEvent event) {
    if (event is AlertPush) ref.invalidate(alertsProvider);
    if (event is RequestPush || event is ClearPush) {
      ref.invalidate(pendingRequestsProvider);
      ref.invalidate(deviceStatusProvider);
    }
    // An open request screen refetches, and shows how the request ended.
    if (event is ClearPush) ref.invalidate(requestProvider(event.requestId));
    if (event is SmsUpdatedPush) {
      // No number in the push: refresh the list and whichever thread is
      // open (an open thread's provider is alive; closed ones are not).
      ref.invalidate(smsConversationsProvider);
      ref.invalidate(smsThreadProvider);
    }
  }

  void _openPairLink(String raw) {
    debugPrint(
      'Vouch: pair link received, valid=${PairLink.parse(raw) != null}',
    );
    if (PairLink.parse(raw) == null) return;
    _router.push('${Routes.pair}?link=${Uri.encodeQueryComponent(raw)}');
  }

  void _startForegroundPoll() {
    _foregroundPoll?.cancel();
    _foregroundPoll = Timer.periodic(foregroundPollEvery, (_) {
      if (ref.read(transportApiProvider) == null) return;
      ref.invalidate(pendingRequestsProvider);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _foregroundPoll?.cancel();
    _openRequest?.cancel();
    _openAlert?.cancel();
    _pushEvents?.cancel();
    _pairLinkSub?.cancel();
    _pairLinks.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Coming back to the app: ask the server about this device again.
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(deviceStatusProvider);
      ref.invalidate(pendingRequestsProvider);
      ref.invalidate(modulesProvider);
      ref.invalidate(alertsProvider);
      ref.invalidate(smsConversationsProvider);
      ref.invalidate(smsThreadProvider);
      // "Also call it whenever the app opens": an app-open check-in, which
      // also delivers any heartbeat answer still owed.
      unawaited(ref.read(checkInServiceProvider).checkIn());
      _startForegroundPoll();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      // Off screen: pushes and the notification layer take over.
      _foregroundPoll?.cancel();
      _foregroundPoll = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Vouch',
      theme: VouchTheme.light(),
      darkTheme: VouchTheme.dark(),
      themeMode: ThemeMode.system,
      routerConfig: _router,
    );
  }
}
