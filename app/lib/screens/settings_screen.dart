import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../app.dart';
import '../dev/sample_requests.dart';
import '../keys/device_key.dart';
import '../pairing/paired_device.dart';
import '../platform/biometry.dart';
import '../push/push_service.dart';
import 'request/request_route_screen.dart';

/// Settings: the paired server, notification health, About.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: ListView(
          children: [
            _Header('Security', theme),
            ListTile(
              leading: const Icon(Icons.vpn_key_outlined),
              title: const Text('Cloudflare Access'),
              subtitle: const Text(
                'Service token, for servers behind Cloudflare Access.',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push(
                Routes.cloudflareAccess(
                  ref.read(pairedDeviceProvider).value?.serverUrl,
                ),
              ),
            ),
            const Divider(),
            // A server without push sends no notifications to check on.
            if (ref.watch(pairedDeviceProvider).value?.pushEnabled ?? true) ...[
              _Header('Notifications', theme),
              ListTile(
                leading: const Icon(Icons.notifications_outlined),
                title: const Text('Notification health'),
                subtitle: Text(
                  Biometry.isApple
                      ? 'Notification and time-sensitive permissions.'
                      : 'Notification and battery permissions.',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(Routes.notificationHealth),
              ),
              const Divider(),
            ],
            if (ref.watch(pairedDeviceProvider).value case final d?) ...[
              _Header('Server', theme),
              ListTile(
                leading: const Icon(Icons.notifications_active_outlined),
                title: const Text('Alerts'),
                subtitle: const Text('What your server warned about lately.'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(Routes.alerts()),
              ),
              // A server setting, not one the app can change: worth a line
              // only when it is off.
              if (d.serverUrl.scheme == 'http')
                ListTile(
                  leading: Icon(
                    Icons.no_encryption_outlined,
                    color: theme.colorScheme.error,
                  ),
                  title: const Text('Not encrypted'),
                  subtitle: Text(
                    '${d.serverName} uses plain HTTP. Fine for testing on '
                    'your own network.',
                  ),
                ),
              if (!d.requireUserAuth)
                ListTile(
                  leading: Icon(
                    Icons.warning_amber,
                    color: theme.colorScheme.error,
                  ),
                  title: Text('${Biometry.title} is off on ${d.serverName}'),
                  subtitle: Text(
                    'Approvals go through without ${Biometry.yours}. '
                    'It is set on the server.',
                  ),
                ),
              ListTile(
                leading: const Icon(Icons.link_off),
                title: const Text('Forget this server'),
                subtitle: Text(
                  'Unpairs ${d.serverName} on this phone and deletes its '
                  'keys. The server still lists the device until it is '
                  'unpaired there too.',
                ),
                isThreeLine: true,
                onTap: () => _forget(context, ref),
              ),
              const Divider(),
            ],
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('About'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push(Routes.about),
            ),
            if (kDebugMode) ...[
              const Divider(),
              _Header('Developer', theme),
              ListTile(
                leading: const Icon(Icons.science_outlined),
                title: const Text('Preview request screen'),
                subtitle: const Text('Fake data; debug builds only.'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(Routes.requestPreview),
              ),
              ListTile(
                leading: const Icon(Icons.notification_add_outlined),
                title: const Text('Simulate request push'),
                subtitle: const Text(
                  'Runs the real push handler on a fake request.',
                ),
                onTap: () async {
                  final r = SampleRequests.signIn();
                  ref.read(requestStoreProvider).put(r);
                  await PushService.instance.simulate({
                    'v': '1',
                    'kind': 'request',
                    'request_id': r.requestId,
                  });
                },
              ),
              ListTile(
                leading: const Icon(Icons.notifications_off_outlined),
                title: const Text('Simulate clear push'),
                onTap: () => PushService.instance.simulate({
                  'v': '1',
                  'kind': 'clear',
                  'request_id': SampleRequests.signIn().requestId,
                }),
              ),
              ListTile(
                leading: const Icon(Icons.key_outlined),
                title: const Text('Key self-test'),
                subtitle: const Text('Keystore and fingerprint channel.'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(Routes.keySelfTest),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

Future<void> _forget(BuildContext context, WidgetRef ref) async {
  final yes = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Forget this server?'),
      // Forgetting is local only: the server keeps this phone's record and
      // keeps notifying it until the phone is unpaired there.
      content: const Text(
        "This phone's keys and pairing will be deleted, so it can no longer "
        'approve or deny anything. Your server still lists this phone and '
        'may keep sending it notifications until you unpair it on the '
        'server. You can pair again with a new code.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Forget'),
        ),
      ],
    ),
  );
  if (yes != true) return;
  final keys = DeviceKeyStore();
  for (final alias in [
    DeviceKeyStore.decisionAlias,
    DeviceKeyStore.transportAlias,
  ]) {
    try {
      await keys.delete(alias);
    } on DeviceKeyException {
      // Already gone.
    }
  }
  await ref.read(pairedDeviceProvider.notifier).clear();
}

class _Header extends StatelessWidget {
  const _Header(this.text, this.theme);

  final String text;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        text,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}
