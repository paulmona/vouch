import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../alerts/alerts.dart';
import '../api/cloudflare_access.dart';
import '../api/vouch_api_client.dart';

/// What the server has warned about lately. [focus]: the alert whose
/// notification was tapped; it is shown first and marked.
class AlertsScreen extends ConsumerStatefulWidget {
  const AlertsScreen({super.key, this.focus});

  final String? focus;

  @override
  ConsumerState<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends ConsumerState<AlertsScreen> {
  @override
  void initState() {
    super.initState();
    // Whatever is on screen has been seen, including later refreshes.
    ref.listenManual(alertsProvider, (_, next) {
      if (next case AsyncData(:final value)) {
        // Not during the build that delivered it.
        Future.microtask(() {
          if (mounted) ref.read(alertsSeenProvider.notifier).markSeen(value);
        });
      }
    }, fireImmediately: true);
  }

  @override
  Widget build(BuildContext context) {
    final alerts = ref.watch(alertsProvider);
    final focus = widget.focus;
    final inList =
        focus == null ||
        (alerts.value?.any((a) => a.alertId == focus) ?? false);
    // An older server has no list, and a new alert may beat the list's
    // refresh: fetch the tapped one on its own.
    final focused = !inList && alerts.hasValue
        ? ref.watch(alertProvider(focus)).value
        : null;
    final list = [?focused, ...?alerts.value];
    return Scaffold(
      appBar: AppBar(title: const Text('Alerts')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(alertsProvider);
          if (focus != null) ref.invalidate(alertProvider(focus));
          await ref.read(alertsProvider.future).catchError((_) => <Alert>[]);
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (alerts case AsyncError(:final error))
              Card(
                child: ListTile(
                  leading: Icon(
                    Icons.cloud_off,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  title: const Text("Couldn't load alerts"),
                  subtitle: Text(
                    isAccessBlocked(error)
                        ? accessBlockedMessage
                        : 'Pull down to try again.',
                  ),
                ),
              ),
            if (alerts.hasValue && list.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 48),
                child: Text(
                  'No alerts in the last 30 days.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            if (alerts.isLoading && !alerts.hasValue)
              const Padding(
                padding: EdgeInsets.only(top: 48),
                child: Center(child: CircularProgressIndicator()),
              ),
            for (final a in list)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: AlertCard(alert: a, focused: a.alertId == focus),
              ),
          ],
        ),
      ),
    );
  }
}

class AlertCard extends StatelessWidget {
  const AlertCard({super.key, required this.alert, this.focused = false});

  final Alert alert;
  final bool focused;

  static String severityLabel(AlertSeverityEnum s) => switch (s) {
    AlertSeverityEnum.critical => 'Critical',
    AlertSeverityEnum.warning => 'Warning',
    _ => 'Info',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (IconData icon, Color colour) = switch (alert.severity) {
      AlertSeverityEnum.critical => (Icons.error, scheme.error),
      AlertSeverityEnum.warning => (Icons.warning_amber, scheme.tertiary),
      _ => (Icons.info_outline, scheme.primary),
    };
    return Card(
      shape: focused
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: scheme.primary, width: 2),
            )
          : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: colour, size: 20),
                const SizedBox(width: 8),
                Text(
                  severityLabel(alert.severity),
                  style: theme.textTheme.labelLarge?.copyWith(color: colour),
                ),
                const Spacer(),
                Text(
                  when(alert.createdAt),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(alert.shownTitle, style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            SelectableText(alert.shownBody, style: theme.textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }

  /// "16 Nov 14:05", in the phone's time zone.
  static String when(DateTime t) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final l = t.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${l.day} ${months[l.month - 1]} ${two(l.hour)}:${two(l.minute)}';
  }
}
