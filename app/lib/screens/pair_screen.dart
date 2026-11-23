import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../api/cloudflare_access.dart';
import '../app.dart';

import '../keys/device_key.dart';
import '../pairing/pair_link.dart';
import '../pairing/paired_device.dart';
import '../pairing/pairing_service.dart';
import '../platform/app_settings.dart';
import '../platform/biometry.dart';
import '../push/push_service.dart';
import '../widgets/vouch_mark.dart';

/// Pairing: scan the QR (or paste the link), a progress step, then success.
class PairScreen extends ConsumerStatefulWidget {
  const PairScreen({super.key, this.initialLink});

  /// A link handed over by the OS (tapped, or `am start -a VIEW`). Shown
  /// for confirmation first: a tapped link never pairs on its own.
  final PairLink? initialLink;

  @override
  ConsumerState<PairScreen> createState() => _PairScreenState();
}

sealed class _Phase {
  const _Phase();
}

class _Scanning extends _Phase {
  const _Scanning();
}

class _Confirm extends _Phase {
  const _Confirm(this.link, {this.fromOutside = true});
  final PairLink link;

  /// Tapped or handed over by the OS, rather than scanned or pasted here.
  final bool fromOutside;
}

class _Pairing extends _Phase {
  const _Pairing(this.step);
  final PairingStep step;
}

class _Paired extends _Phase {
  const _Paired(this.device);
  final PairedDevice device;
}

class _Failed extends _Phase {
  const _Failed(this.error);
  final PairingException error;
}

class _PairScreenState extends ConsumerState<PairScreen> {
  late _Phase _phase = switch (widget.initialLink) {
    final l? => _Confirm(l),
    null => const _Scanning(),
  };
  bool _handled = false;

  /// Debug only: an emulator's attestation chains to a software root, which
  /// the server rightly refuses; turning this off sends empty chains so the
  /// flow can be exercised against a dev server with the policy off.
  bool _sendAttestation = true;

  /// A scanned or pasted link. Plain HTTP gets the confirmation and its
  /// warning first, and so does a link when a Cloudflare Access token is
  /// waiting: the token goes only to a host shown here and confirmed.
  Future<void> _onLink(PairLink link) async {
    final confirmFirst =
        link.server.scheme == 'http' ||
        await CloudflareAccessStore.instance.read(null) != null;
    if (!mounted) return;
    if (confirmFirst) {
      setState(() => _phase = _Confirm(link, fromOutside: false));
    } else {
      await _pair(link);
    }
  }

  Future<void> _pair(PairLink link, {bool confirmed = false}) async {
    // Pairing replaces this phone's keys before the server has said yes, so
    // a bad link would break a working pairing. Forget it first.
    if (_handled || ref.read(pairedDeviceProvider).value != null) return;
    _handled = true;
    setState(() => _phase = const _Pairing(PairingStep.creatingKeys));
    final service = PairingService(
      keys: DeviceKeyStore(),
      store: ref.read(pairedDeviceStoreProvider),
      pushToken: () async {
        // Give Firebase a moment if the token is still on its way.
        final push = PushService.instance;
        if (push.token != null) return push.token;
        if (!push.available) return null;
        try {
          return await push.onTokenRefresh.first.timeout(
            const Duration(seconds: 8),
          );
        } on Object {
          return null;
        }
      },
      // A build with no Firebase config pairs without notifications.
      pushAvailable: () => PushService.instance.available,
    );
    try {
      final name = await AppSettings().deviceName();
      final device = await service.pair(
        link,
        deviceName: name,
        sendAttestation: _sendAttestation,
        sendPendingAccessToken: confirmed,
        onStep: (s) {
          if (mounted) setState(() => _phase = _Pairing(s));
        },
      );
      await ref.read(pairedDeviceProvider.notifier).set(device);
      // Pairing is the moment to ask for what a request needs later; a
      // server without push sends nothing to allow.
      if (device.pushEnabled) {
        await PushService.instance.notifications
            .requestNotificationsPermission();
      }
      if (mounted) setState(() => _phase = _Paired(device));
    } on PairingException catch (e) {
      if (mounted) setState(() => _phase = _Failed(e));
    } catch (e) {
      if (mounted) {
        setState(
          () => _phase = _Failed(
            PairingException(PairingError.server, 'Pairing failed: $e'),
          ),
        );
      }
    }
  }

  void _retry() => setState(() {
    _handled = false;
    _phase = const _Scanning();
  });

  @override
  Widget build(BuildContext context) {
    final paired = ref.watch(pairedDeviceProvider).value;
    if (paired != null && _phase is! _Pairing && _phase is! _Paired) {
      return _AlreadyPairedView(serverName: paired.serverName);
    }
    return switch (_phase) {
      _Scanning() => _ScanView(
        onLink: _onLink,
        sendAttestation: _sendAttestation,
        onSendAttestation: (v) => setState(() => _sendAttestation = v),
      ),
      _Confirm(:final link, :final fromOutside) => _ConfirmView(
        link: link,
        fromOutside: fromOutside,
        sendAttestation: _sendAttestation,
        onSendAttestation: (v) => setState(() => _sendAttestation = v),
        onPair: () => _pair(link, confirmed: true),
        onCancel: () => setState(() => _phase = const _Scanning()),
      ),
      _Pairing(:final step) => _ProgressView(step: step),
      _Paired(:final device) => _SuccessView(device: device),
      _Failed(:final error) => _FailedView(error: error, onRetry: _retry),
    };
  }
}

class _ScanView extends StatefulWidget {
  const _ScanView({
    required this.onLink,
    required this.sendAttestation,
    required this.onSendAttestation,
  });

  final ValueChanged<PairLink> onLink;
  final bool sendAttestation;
  final ValueChanged<bool> onSendAttestation;

  @override
  State<_ScanView> createState() => _ScanViewState();
}

class _ScanViewState extends State<_ScanView> {
  final _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
  );
  String? _lastBad;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    for (final b in capture.barcodes) {
      final raw = b.rawValue;
      if (raw == null) continue;
      final link = PairLink.parse(raw);
      if (link != null) {
        widget.onLink(link);
        return;
      }
      if (_lastBad != raw) setState(() => _lastBad = raw);
    }
  }

  Future<void> _paste() async {
    final text = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _PasteSheet(),
    );
    if (text == null || !mounted) return;
    final link = PairLink.parse(text);
    if (link == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            PairLink.isPlainHttpToPublicHost(text)
                ? PairLink.plainHttpRefused
                : "That isn't a Vouch pairing link.",
          ),
        ),
      );
      return;
    }
    widget.onLink(link);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Pair with a server')),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      MobileScanner(
                        controller: _controller,
                        onDetect: _onDetect,
                        errorBuilder: (context, error) => Container(
                          color: theme.colorScheme.surfaceContainer,
                          alignment: Alignment.center,
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            'Camera unavailable. Paste the link instead.',
                            style: theme.textTheme.bodyLarge,
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                      IgnorePointer(
                        child: Center(
                          child: Container(
                            width: 240,
                            height: 240,
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.9),
                                width: 3,
                              ),
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    switch (_lastBad) {
                      null =>
                        'Point the camera at the QR code on your '
                            "server's Devices page or setup command.",
                      final bad when PairLink.isPlainHttpToPublicHost(bad) =>
                        PairLink.plainHttpRefused,
                      _ => "That QR code isn't a Vouch pairing link.",
                    },
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: _lastBad == null
                          ? theme.colorScheme.onSurfaceVariant
                          : theme.colorScheme.error,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _paste,
                    icon: const Icon(Icons.link),
                    label: const Text('Enter the link instead'),
                  ),
                  TextButton(
                    onPressed: () => context.push(Routes.cloudflareAccess()),
                    child: const Text('Behind Cloudflare Access?'),
                  ),
                  if (kDebugMode)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Send key attestation'),
                      subtitle: const Text(
                        'Off for emulators (software attestation).',
                      ),
                      value: widget.sendAttestation,
                      onChanged: widget.onSendAttestation,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PasteSheet extends StatefulWidget {
  const _PasteSheet();

  @override
  State<_PasteSheet> createState() => _PasteSheetState();
}

class _PasteSheetState extends State<_PasteSheet> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        16,
        24,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Pairing link', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          TextField(
            controller: _text,
            autofocus: true,
            minLines: 1,
            maxLines: 4,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: const InputDecoration(
              hintText: 'vouch://pair?v=1&server=…&token=…',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (v) => Navigator.of(context).pop(v),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(_text.text),
            child: const Text('Pair'),
          ),
        ],
      ),
    );
  }
}

class _ProgressView extends StatelessWidget {
  const _ProgressView({required this.step});

  final PairingStep step;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final steps = [
      (PairingStep.creatingKeys, 'Creating this phone\'s keys'),
      (PairingStep.confirming, 'Confirming ${Biometry.withYours}'),
      (PairingStep.registering, 'Registering with the server'),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Pairing')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            for (final (s, label) in steps)
              ListTile(
                leading: s.index < step.index
                    ? Icon(Icons.check_circle, color: theme.colorScheme.primary)
                    : s == step
                    ? const SizedBox.square(
                        dimension: 24,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      )
                    : Icon(
                        Icons.radio_button_unchecked,
                        color: theme.colorScheme.outline,
                      ),
                title: Text(label),
              ),
          ],
        ),
      ),
    );
  }
}

class _SuccessView extends StatefulWidget {
  const _SuccessView({required this.device});

  final PairedDevice device;

  @override
  State<_SuccessView> createState() => _SuccessViewState();
}

class _SuccessViewState extends State<_SuccessView> {
  bool? _batteryOk;

  @override
  void initState() {
    super.initState();
    _refreshBattery();
  }

  Future<void> _refreshBattery() async {
    final ok = await AppSettings().isIgnoringBatteryOptimizations();
    if (mounted) setState(() => _batteryOk = ok);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final d = widget.device;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    const SizedBox(height: 32),
                    const VouchMark(size: 64),
                    const SizedBox(height: 24),
                    Text(
                      'Paired with ${d.serverName}',
                      style: theme.textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      d.userAuthBound == 'attested'
                          ? 'Your server verified that approvals from this '
                                'phone need ${Biometry.yours}.'
                          : d.userAuthBound == 'none'
                          ? 'This pairing is not ${Biometry.bound} on the '
                                'server (development mode).'
                          : 'Approvals from this phone need ${Biometry.yours}.',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),
                    // Android only: iOS has no battery allow-list, and
                    // time-sensitive notifications need no opt-in.
                    if (!Biometry.isApple && widget.device.pushEnabled)
                      Card(
                        child: ListTile(
                          leading: Icon(
                            _batteryOk == true
                                ? Icons.check_circle
                                : Icons.battery_saver,
                            color: _batteryOk == true
                                ? scheme.primary
                                : scheme.onSurfaceVariant,
                          ),
                          title: const Text('Let Vouch run in the background'),
                          subtitle: Text(
                            _batteryOk == true
                                ? 'Battery optimisation is off for Vouch.'
                                : 'Samsung and others delay pushes to '
                                      'optimised apps. Allow unrestricted '
                                      'battery use so requests arrive in time.',
                          ),
                          trailing: _batteryOk == true
                              ? null
                              : FilledButton.tonal(
                                  onPressed: () async {
                                    await AppSettings()
                                        .requestIgnoreBatteryOptimizations();
                                    await Future<void>.delayed(
                                      const Duration(seconds: 1),
                                    );
                                    await _refreshBattery();
                                  },
                                  child: const Text('Allow'),
                                ),
                          isThreeLine: _batteryOk != true,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  child: const Text('Done'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FailedView extends StatelessWidget {
  const _FailedView({required this.error, required this.onRetry});

  final PairingException error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = switch (error.error) {
      PairingError.cancelled => 'Pairing not confirmed',
      PairingError.invalidToken => 'This code has expired',
      PairingError.biometricsUnavailable => '${Biometry.title} needed',
      PairingError.network => "Couldn't reach the server",
      PairingError.accessBlocked => 'Blocked by Cloudflare Access',
      _ => "Couldn't pair",
    };
    return Scaffold(
      appBar: AppBar(title: const Text('Pair with a server')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 56,
                        color: theme.colorScheme.error,
                      ),
                      const SizedBox(height: 20),
                      Text(
                        title,
                        style: theme.textTheme.headlineSmall,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        error.message,
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
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton(
                    onPressed: onRetry,
                    child: const Text('Try again'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    child: const Text('Cancel'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Already paired: a link or a scan must not touch the keys a working
/// pairing depends on. Forgetting the server first is a deliberate step.
class _AlreadyPairedView extends StatelessWidget {
  const _AlreadyPairedView({required this.serverName});

  final String serverName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Pair with a server')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Icon(
              Icons.verified_user_outlined,
              size: 56,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 20),
            Text(
              'Already paired with $serverName',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'To pair with a different server, forget $serverName in '
              'Settings first, then open the link again.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text('OK'),
            ),
          ],
        ),
      ),
    );
  }
}

/// A link arrived from outside the app: say where it points and ask.
class _ConfirmView extends StatelessWidget {
  const _ConfirmView({
    required this.link,
    required this.fromOutside,
    required this.sendAttestation,
    required this.onSendAttestation,
    required this.onPair,
    required this.onCancel,
  });

  final PairLink link;
  final bool fromOutside;
  final bool sendAttestation;
  final ValueChanged<bool> onSendAttestation;
  final VoidCallback onPair;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final server = link.server;
    final host = server.hasPort ? '${server.host}:${server.port}' : server.host;
    return Scaffold(
      appBar: AppBar(title: const Text('Pair with a server')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Icon(
              Icons.link,
              size: 56,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 20),
            Text(
              'Pair this phone with',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              host,
              style: theme.textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            if (server.scheme != 'https')
              Text(
                'Not encrypted. Fine for testing on your own network.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.error,
                ),
                textAlign: TextAlign.center,
              )
            else if (fromOutside)
              Text(
                'The link came from outside the app. Only continue if you '
                'asked your server for it.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            FutureBuilder(
              future: CloudflareAccessStore.instance.read(null),
              builder: (context, snap) => snap.data == null
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'Pair sends your Cloudflare Access service token to '
                        '$host. Only continue if this is your server.',
                        style: theme.textTheme.bodyMedium,
                        textAlign: TextAlign.center,
                      ),
                    ),
            ),
            const SizedBox(height: 24),
            if (kDebugMode)
              SwitchListTile(
                title: const Text('Send key attestation'),
                subtitle: const Text(
                  'Off for emulators (software attestation).',
                ),
                value: sendAttestation,
                onChanged: onSendAttestation,
              ),
            const SizedBox(height: 8),
            FilledButton(onPressed: onPair, child: const Text('Pair')),
            const SizedBox(height: 8),
            OutlinedButton(onPressed: onCancel, child: const Text('Cancel')),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () =>
                  context.push(Routes.cloudflareAccess(link.server)),
              child: const Text('Behind Cloudflare Access?'),
            ),
          ],
        ),
      ),
    );
  }
}
