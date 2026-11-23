import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../api/cloudflare_access.dart';
import '../../api/vouch_api_client.dart';
import '../../app.dart';
import '../../pairing/paired_device.dart';
import '../../server/modules.dart';
import '../../sms/phone_format.dart';
import '../../sms/sms_providers.dart';

/// The Messages tab: one row per number, most recent first.
class MessagesTab extends ConsumerWidget {
  const MessagesTab({super.key, required this.device});

  final PairedDevice device;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(smsConversationsProvider, (_, next) {
      // A 404 on the list may mean SMS was switched off since the tabs were
      // drawn. Only /v1/server/modules decides that: ask it again, and the
      // tab goes away if so.
      if (next.error case ApiException(code: 404)) {
        ref.invalidate(modulesProvider);
      }
    });
    final conversations = ref.watch(smsConversationsProvider);
    final list = RefreshIndicator(
      onRefresh: () => ref.refresh(smsConversationsProvider.future),
      child: switch (conversations) {
        AsyncData(value: final list) when list.isNotEmpty => ListView.separated(
          itemCount: list.length,
          separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
          itemBuilder: (context, i) => _ConversationRow(list[i]),
        ),
        AsyncData() => _Message(
          icon: Icons.chat_bubble_outline,
          title: 'No messages yet',
          body:
              'Texts your agent sends and receives on ${device.serverName} '
              'will show here.',
        ),
        AsyncError(:final error) => _Message(
          icon: Icons.cloud_off,
          title: "Couldn't load messages",
          body: isAccessBlocked(error)
              ? accessBlockedMessage
              : 'Pull down to try again.',
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.contacts_outlined),
          title: const Text('Permitted contacts'),
          subtitle: const Text('Who your agent may text'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push(Routes.smsContacts),
        ),
        const Divider(height: 1),
        Expanded(child: list),
      ],
    );
  }
}

class _ConversationRow extends StatelessWidget {
  const _ConversationRow(this.c);

  final SmsConversation c;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final name = c.contactName ?? formatPhone(c.phone);
    final unread = c.unreadCount > 0;
    final last = c.lastMessage;
    final preview = last.direction == SmsMessageDirectionEnum.outbound
        ? 'Agent: ${last.text}'
        : last.text;
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: scheme.primaryContainer,
        foregroundColor: scheme.onPrimaryContainer,
        child: c.contactName == null
            ? const Icon(Icons.person_outline)
            : Text(name.characters.first.toUpperCase()),
      ),
      title: Text(
        name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: unread ? const TextStyle(fontWeight: FontWeight.w700) : null,
      ),
      subtitle: Text(preview, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            smsTime(last.at),
            style: theme.textTheme.bodySmall?.copyWith(
              color: unread ? scheme.primary : scheme.onSurfaceVariant,
            ),
          ),
          if (unread) ...[
            const SizedBox(height: 4),
            Badge(
              label: Text('${c.unreadCount}'),
              backgroundColor: scheme.primary,
            ),
          ],
        ],
      ),
      onTap: () => context.push(Routes.smsThread(c.phone, name: c.contactName)),
    );
  }
}

/// "14:05" today, "Mon" this week, "2026-11-03" before that.
String smsTime(DateTime at, {DateTime? now}) {
  final l = at.toLocal();
  final n = (now ?? DateTime.now()).toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  final today = DateTime(n.year, n.month, n.day);
  final day = DateTime(l.year, l.month, l.day);
  if (day == today) return '${two(l.hour)}:${two(l.minute)}';
  if (today.difference(day).inDays < 7) {
    return const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][l.weekday -
        1];
  }
  return '${l.year}-${two(l.month)}-${two(l.day)}';
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Scrollable so pull-to-refresh works on an empty or failed list.
    return LayoutBuilder(
      builder: (context, box) => ListView(
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(minHeight: box.maxHeight),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      icon,
                      size: 56,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 16),
                    Text(title, style: theme.textTheme.titleLarge),
                    const SizedBox(height: 8),
                    Text(
                      body,
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
        ],
      ),
    );
  }
}
