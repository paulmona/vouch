import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vouch_api/api.dart';

import '../../dev/sample_requests.dart';
import '../../model/decision.dart';
import '../../push/push_service.dart';
import '../../requests/decision_service.dart';
import '../../requests/request_providers.dart';
import 'request_screen.dart';

/// Requests the app holds locally, by id: the debug-simulated ones, and the
/// fallback when fetching one from the server fails.
class RequestStore {
  final _byId = <String, ApprovalRequest>{};

  ApprovalRequest? find(String id) => _byId[id];

  void put(ApprovalRequest r) => _byId[r.requestId] = r;
}

final requestStoreProvider = Provider<RequestStore>((ref) => RequestStore());

/// Decides when the phone is not paired. Only a debug build has one (the
/// fake decider, for simulated pushes); kDebugMode is a constant, so a
/// release build leaves FakeDecider out and an unpaired tap sends nothing
/// and claims nothing.
final unpairedDeciderProvider = Provider<DecideCallback?>(
  (ref) => kDebugMode ? FakeDecider().call : null,
);

const notPairedMessage =
    'This phone is not paired with a server. Nothing was sent.';

/// `/requests/:id`: opened from a notification tap or from Home.
/// Looks the request up, shows it, and records push-to-screen timing.
class RequestRouteScreen extends ConsumerStatefulWidget {
  const RequestRouteScreen({
    super.key,
    required this.requestId,
    this.fromPush = false,
  });

  final String requestId;

  /// Opened from a notification: after the decision the app gets out of the
  /// way (the activity finishes) rather than going back to Home.
  final bool fromPush;

  @override
  ConsumerState<RequestRouteScreen> createState() => _RequestRouteScreenState();
}

class _RequestRouteScreenState extends ConsumerState<RequestRouteScreen> {
  Duration? _pushToScreen;

  /// The server's newer version after a `shown_mismatch`. Shown and signed
  /// from then on, so the screen and the digest always agree.
  ApprovalRequest? _changed;

  @override
  void initState() {
    super.initState();
    PrefsPushReceipts().received(widget.requestId).then((t) {
      if (t != null && mounted) {
        setState(() => _pushToScreen = DateTime.now().difference(t));
      }
    });
  }

  /// Decision made: from a notification, hand the phone back to whatever
  /// was in front before the tap; from Home, back to Home (which refreshes).
  void _leave(BuildContext context) {
    // iOS ignores SystemNavigator.pop (an app may not close itself), which
    // left the outcome page up; there it goes back to Home like a Home tap.
    if (widget.fromPush && defaultTargetPlatform != TargetPlatform.iOS) {
      SystemNavigator.pop();
    } else {
      // Pushed on top of Home by go_router; a plain Navigator pop takes it
      // off (and works in a bare MaterialApp in tests).
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final loaded = ref.watch(requestProvider(widget.requestId));
    final request =
        _changed ??
        switch (loaded) {
          AsyncData(:final value) => value,
          AsyncError() => ref.read(requestStoreProvider).find(widget.requestId),
          _ => null,
        };
    if (loaded is AsyncLoading && request == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (request == null) {
      return const _Unavailable();
    }
    // Paired: the decision key signs after the fingerprint prompt.
    final service = ref.watch(decisionServiceProvider);
    final unpaired = ref.watch(unpairedDeciderProvider);
    return Stack(
      children: [
        RequestScreen(
          request: request,
          onDecide: (Decision d) async {
            if (service == null) {
              return unpaired?.call(d) ?? const Failed(notPairedMessage);
            }
            final outcome = await service.decide(request, d);
            if (outcome is ShownChanged && mounted) {
              setState(() => _changed = outcome.request);
            }
            return outcome;
          },
          onFinished: (_) => _leave(context),
        ),
        // A latency check for development; never in a release build.
        if (kDebugMode && _pushToScreen != null)
          Positioned(
            right: 8,
            top: MediaQuery.paddingOf(context).top + 4,
            child: IgnorePointer(
              child: Text(
                'push→screen ${_pushToScreen!.inMilliseconds} ms',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _Unavailable extends StatelessWidget {
  const _Unavailable();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Request')),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.inbox_outlined,
                  size: 56,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(height: 20),
                Text(
                  'This request is no longer available',
                  style: theme.textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'It may have expired or been answered on another device.',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
