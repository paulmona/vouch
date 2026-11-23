import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vouch_api/api.dart';

import '../alerts/alerts.dart';
import '../api/cloudflare_access.dart';
import '../app.dart';
import '../keys/key_error_text.dart';
import '../pairing/device_session.dart';
import '../pairing/paired_device.dart';
import '../platform/biometry.dart';
import '../push/push_service.dart';
import '../requests/decision_service.dart';
import '../requests/request_kind.dart';
import '../requests/request_providers.dart';
import '../server/modules.dart';
import '../theme/brand.dart';
import '../widgets/vouch_mark.dart';
import 'sms/messages_tab.dart';

/// Home: the paired server, last contact time and pending requests. When
/// the server runs SMS a bottom bar adds Messages; with one module
/// there is no bar at all.
const noPushFromServerText =
    'No notifications from this server. Open Vouch to check for requests, '
    'or pull down to refresh.';

const noPushInBuildText =
    'This copy of Vouch has no notifications. Open Vouch to check for '
    'requests, or pull down to refresh. For notifications, build Vouch '
    'with your own Firebase project.';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final paired = ref.watch(pairedDeviceProvider);
    final device = paired.value;
    final modules = ref.watch(modulesProvider).value ?? defaultModules;
    final tabs = device != null && modules.sms;
    final tab = tabs ? _tab : 0;
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            VouchMark(size: 28),
            SizedBox(width: 12),
            Text(Brand.productName),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push(Routes.settings),
          ),
        ],
      ),
      body: SafeArea(
        child: switch (paired) {
          AsyncData(value: final d?) when tab == 1 => MessagesTab(device: d),
          AsyncData(value: final d?) => _PairedHome(
            device: d,
            credentials: modules.credentials,
          ),
          AsyncData() => const _NotPaired(),
          AsyncError() => const _NotPaired(),
          _ => const Center(child: CircularProgressIndicator()),
        },
      ),
      bottomNavigationBar: tabs
          ? NavigationBar(
              selectedIndex: tab,
              onDestinationSelected: (i) => setState(() => _tab = i),
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.verified_user_outlined),
                  selectedIcon: Icon(Icons.verified_user),
                  label: 'Approvals',
                ),
                NavigationDestination(
                  icon: Icon(Icons.chat_bubble_outline),
                  selectedIcon: Icon(Icons.chat_bubble),
                  label: 'Messages',
                ),
              ],
            )
          : null,
    );
  }
}

class _PairedHome extends ConsumerWidget {
  const _PairedHome({required this.device, required this.credentials});

  final PairedDevice device;

  /// Off: password sign-in requests are not this server's business, so
  /// none are listed even if one is still pending from before the switch.
  final bool credentials;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = ref.watch(deviceStatusProvider);
    final keyGone = ref.watch(decisionKeyPresentProvider).value == false;
    // A dot says it all when connected; words only when something is wrong.
    final (Color dot, String dotLabel, String? problem) = switch (status) {
      AsyncData(value: DeviceOnline()) when keyGone => (
        scheme.error,
        "Can't approve",
        noDecisionKeyText,
      ),
      AsyncData(value: DeviceOnline()) => (_green, 'Connected', null),
      AsyncData(value: DeviceUnpaired()) => (
        scheme.error,
        'Not connected',
        'This phone was unpaired on the server. Forget it in Settings and '
            'pair again.',
      ),
      AsyncData(value: DeviceUnreachable(:final message)) => (
        scheme.error,
        'Not connected',
        message,
      ),
      _ => (scheme.outline, 'Checking', null),
    };
    final notes = [
      ?problem,
      if (device.rekeyRequired)
        'Your server changed its ${Biometry.name} policy. Pair again to keep '
            'approving.',
    ];
    ref.watch(pendingRequestsInvalidator);
    final pending = ref
        .watch(pendingRequestsProvider)
        .whenData(
          (list) => credentials
              ? list
              : [
                  for (final r in list)
                    if (r.kind != ApprovalRequestKindEnum.signIn) r,
                ],
        );
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(pendingRequestsProvider);
        ref.invalidate(modulesProvider);
        ref.invalidate(deviceStatusProvider);
        ref.invalidate(alertsProvider);
        await ref.read(deviceStatusProvider.future);
      },
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.dns_outlined, color: scheme.primary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              device.serverName,
                              style: theme.textTheme.titleMedium,
                            ),
                            Text(
                              device.serverUrl.host,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Semantics(
                        label: dotLabel,
                        child: Tooltip(
                          message: dotLabel,
                          child: Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: dot,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (!device.pushEnabled)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        ref.watch(pushAvailableProvider)
                            ? noPushFromServerText
                            : noPushInBuildText,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  for (final n in notes)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        n,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.error,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const _AlertsCard(),
          // Nothing waiting is the normal state: say nothing then.
          if (pending is AsyncError ||
              (pending.value?.isNotEmpty ?? false)) ...[
            const SizedBox(height: 24),
            Text('Pending requests', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
          ],
          switch (pending) {
            AsyncData(value: final list) when list.isNotEmpty => Card(
              child: Column(
                children: [
                  for (final r in list)
                    ListTile(
                      leading: Icon(Icons.lock_clock, color: scheme.primary),
                      title: Text(
                        r.isSmsContact
                            ? '${r.shownAgent} · text ${r.shownNumber}'
                            : '${r.shownAgent} · ${r.shownSite}',
                      ),
                      subtitle: Text(
                        r.shownLoginTitle == null
                            ? 'Expires ${_clock(r.expiresAt)}'
                            : '${r.shownLoginTitle} · expires '
                                  '${_clock(r.expiresAt)}',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push(Routes.request(r.requestId)),
                    ),
                ],
              ),
            ),
            AsyncError(:final error) => Card(
              child: ListTile(
                leading: Icon(Icons.cloud_off, color: scheme.error),
                title: const Text("Couldn't check for requests"),
                subtitle: Text(
                  isAccessBlocked(error)
                      ? accessBlockedMessage
                      : 'Pull down to try again.',
                ),
              ),
            ),
            _ => const SizedBox.shrink(),
          },
        ],
      ),
    );
  }

  static String _clock(DateTime t) {
    final l = t.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(l.hour)}:${two(l.minute)}';
  }
}

/// Always on Home, so an alert can be read again after its notification
/// is gone. Stands out while one is unopened: the server thinks something
/// is wrong, and the notification may have been missed or never sent.
class _AlertsCard extends ConsumerWidget {
  const _AlertsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final fresh = ref.watch(newAlertsProvider);
    final all = ref.watch(alertsProvider).value;
    final critical = fresh.any((a) => a.severity == AlertSeverityEnum.critical);
    final onCard = critical ? scheme.onErrorContainer : null;
    final (String title, String subtitle) = switch (fresh) {
      [final one] => (one.shownTitle, 'New alert. Tap to read.'),
      [final newest, ...] => ('${fresh.length} new alerts', newest.shownTitle),
      [] => (
        'Alerts',
        switch (all?.length) {
          null => 'Recent alerts from your server.',
          0 => 'None in the last 30 days.',
          1 => '1 in the last 30 days.',
          final n => '$n in the last 30 days.',
        },
      ),
    };
    return Card(
      color: critical ? scheme.errorContainer : null,
      child: ListTile(
        leading: Icon(
          fresh.isEmpty
              ? Icons.notifications_outlined
              : critical
              ? Icons.error
              : Icons.warning_amber,
          color: onCard ?? scheme.primary,
        ),
        title: Text(title, style: TextStyle(color: onCard)),
        subtitle: Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: onCard),
        ),
        trailing: Icon(Icons.chevron_right, color: onCard),
        onTap: () => context.push(Routes.alerts()),
      ),
    );
  }
}

/// Connected. Not in the brand scheme, which has no "good" colour.
const _green = Color(0xFF34C759);

class _NotPaired extends StatelessWidget {
  const _NotPaired();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(
                Icons.phonelink_lock_outlined,
                size: 56,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 20),
              Text(
                'Not paired yet',
                style: theme.textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Pair this phone with your Vouch server to start '
                'approving requests. You will need the QR code from the '
                "server's Devices page or setup command.",
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => context.push(Routes.pair),
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('Pair with a server'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
