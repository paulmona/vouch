import 'package:flutter/material.dart';

import '../platform/biometry.dart';
import '../push/push_service.dart';

/// Settings → Notification health: can a request actually reach the screen?
/// Notification permission (Android 13+) and, later, battery optimisation.
class NotificationHealthScreen extends StatefulWidget {
  const NotificationHealthScreen({super.key});

  @override
  State<NotificationHealthScreen> createState() =>
      _NotificationHealthScreenState();
}

class _NotificationHealthScreenState extends State<NotificationHealthScreen>
    with WidgetsBindingObserver {
  bool? _enabled;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final enabled = await PushService.instance.notifications
        .notificationsEnabled();
    if (mounted) setState(() => _enabled = enabled);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final push = PushService.instance;
    final notifications = push.notifications;
    return Scaffold(
      appBar: AppBar(title: const Text('Notification health')),
      body: SafeArea(
        child: ListView(
          children: [
            _Row(
              icon: Icons.cloud_outlined,
              title: 'Push service',
              status: push.available
                  ? (push.token != null ? 'Connected' : 'Waiting for a token')
                  : 'Unavailable in this build',
              ok: push.available && push.token != null,
            ),
            _Row(
              icon: Icons.notifications_outlined,
              title: 'Notifications',
              status: switch (_enabled) {
                null => 'Checking…',
                true => 'Allowed',
                false => 'Blocked. Requests cannot reach you.',
              },
              ok: _enabled,
              action: _enabled == false
                  ? FilledButton.tonal(
                      onPressed: () async {
                        await notifications.requestNotificationsPermission();
                        await _refresh();
                      },
                      child: const Text('Allow'),
                    )
                  : null,
            ),
            if (Biometry.isApple)
              const _Row(
                icon: Icons.notifications_active_outlined,
                title: 'Time-sensitive requests',
                status:
                    'Requests break through Focus modes and show on the '
                    'lock screen. Tap one to open it.',
                ok: null,
              )
            else ...[
              const _Row(
                icon: Icons.lock_outline,
                title: 'Locked phone',
                status:
                    'A request alerts with sound. Unlock the phone to '
                    'answer it.',
                ok: null,
              ),
              const _Row(
                icon: Icons.battery_saver,
                title: 'Battery optimisation',
                status: 'Checked during pairing.',
                ok: null,
              ),
            ],
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'A request is time-limited: if nobody answers it in time, it '
                'is denied.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.title,
    required this.status,
    required this.ok,
    this.action,
  });

  final IconData icon;
  final String title;
  final String status;
  final bool? ok;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(status),
      trailing:
          action ??
          switch (ok) {
            true => Icon(Icons.check_circle, color: scheme.primary),
            false => Icon(Icons.error, color: scheme.error),
            null => null,
          },
      isThreeLine: status.length > 40,
    );
  }
}
