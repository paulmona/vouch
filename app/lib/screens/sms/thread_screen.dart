import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/vouch_api_client.dart';
import '../../sms/phone_format.dart';
import '../../sms/sms_providers.dart';

/// Said wherever something is deleted.
const providerKeepsCopy =
    'They are removed from Vouch only. voip.ms keeps its own copy.';

/// One conversation: newest at the bottom, older pages load as the
/// owner scrolls up. Inbound on the left; what the agent sent on the right.
/// Long-press a message to select messages to delete; the menu
/// deletes the whole conversation.
class ThreadScreen extends ConsumerStatefulWidget {
  const ThreadScreen({super.key, required this.phone, this.name});

  /// E.164.
  final String phone;

  /// The contact's name when the list knew it.
  final String? name;

  @override
  ConsumerState<ThreadScreen> createState() => _ThreadScreenState();
}

class _ThreadScreenState extends ConsumerState<ThreadScreen> {
  final _selected = <String>{};
  bool _busy = false;

  String get phone => widget.phone;

  void _toggle(SmsMessage m) => setState(() {
    if (!_selected.remove(m.messageId)) _selected.add(m.messageId);
  });

  Future<bool> _confirm(String title, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: const Text(providerKeepsCopy),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
              child: Text(action),
            ),
          ],
        ),
      ) ==
      true;

  Future<void> _deleteSelected() async {
    final n = _selected.length;
    final what = n == 1 ? 'this message' : '$n messages';
    if (!await _confirm('Delete $what?', 'Delete') || !mounted) return;
    setState(() => _busy = true);
    final error = await ref
        .read(smsThreadProvider(phone).notifier)
        .deleteMessages({..._selected});
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (error == null) _selected.clear();
    });
    _say(error ?? (n == 1 ? 'Message deleted' : '$n messages deleted'));
  }

  Future<void> _deleteConversation() async {
    final who = widget.name ?? formatPhone(phone);
    if (!await _confirm('Delete every message with $who?', 'Delete all') ||
        !mounted) {
      return;
    }
    setState(() => _busy = true);
    final error = await ref
        .read(smsThreadProvider(phone).notifier)
        .deleteConversation();
    if (!mounted) return;
    setState(() => _busy = false);
    if (error != null) return _say(error);
    _say('Conversation deleted');
    await Navigator.of(context).maybePop();
  }

  void _copySelected(SmsThreadState s) {
    final m = s.messages.firstWhere((m) => _selected.contains(m.messageId));
    Clipboard.setData(ClipboardData(text: m.text));
    setState(_selected.clear);
    _say('Copied');
  }

  void _say(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context) {
    final thread = ref.watch(smsThreadProvider(phone));
    final theme = Theme.of(context);
    final selecting = _selected.isNotEmpty;
    return PopScope(
      // Back leaves selection first, like Messages.
      canPop: !selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(_selected.clear);
      },
      child: Scaffold(
        appBar: selecting
            ? AppBar(
                leading: IconButton(
                  tooltip: 'Cancel selection',
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(_selected.clear),
                ),
                title: Text('${_selected.length} selected'),
                actions: [
                  if (_selected.length == 1 && thread.value != null)
                    IconButton(
                      tooltip: 'Copy',
                      icon: const Icon(Icons.copy),
                      onPressed: () => _copySelected(thread.value!),
                    ),
                  IconButton(
                    tooltip: 'Delete',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: _busy ? null : _deleteSelected,
                  ),
                ],
              )
            : AppBar(
                title: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.name ?? formatPhone(phone)),
                    if (widget.name != null)
                      Text(
                        formatPhone(phone),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
                actions: [
                  PopupMenuButton<void>(
                    enabled: !_busy && thread.hasValue,
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        onTap: _deleteConversation,
                        child: const Text('Delete conversation'),
                      ),
                    ],
                  ),
                ],
              ),
        body: SafeArea(
          child: switch (thread) {
            AsyncData(:final value) when value.messages.isEmpty => const Center(
              child: Text('No messages with this number.'),
            ),
            AsyncData(:final value) => _Messages(
              phone: phone,
              state: value,
              selected: _selected,
              onLongPress: _toggle,
              onTap: selecting ? _toggle : null,
            ),
            // Deleted (e.g. on the other phone) while this screen was open
            // or the link was old: say so, nothing to retry.
            AsyncError(error: ApiException(code: 404)) => const Center(
              child: Text('This conversation has been deleted.'),
            ),
            AsyncError() => Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text("Couldn't load this conversation."),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: () => ref.invalidate(smsThreadProvider(phone)),
                    child: const Text('Try again'),
                  ),
                ],
              ),
            ),
            _ => const Center(child: CircularProgressIndicator()),
          },
        ),
      ),
    );
  }
}

class _Messages extends ConsumerWidget {
  const _Messages({
    required this.phone,
    required this.state,
    required this.selected,
    required this.onLongPress,
    this.onTap,
  });

  final String phone;
  final SmsThreadState state;
  final Set<String> selected;
  final void Function(SmsMessage) onLongPress;

  /// Set while selecting: a tap adds or removes a message.
  final void Function(SmsMessage)? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final messages = state.messages;
    // Reversed: index 0 (the newest) sits at the bottom, and scrolling up
    // walks back in time. The extra last item is the "older" loader.
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n.metrics.extentAfter < 400) {
          ref.read(smsThreadProvider(phone).notifier).loadOlder();
        }
        return false;
      },
      child: ListView.builder(
        reverse: true,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: messages.length + (state.hasOlder ? 1 : 0),
        itemBuilder: (context, i) {
          if (i == messages.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final m = messages[i];
          final older = i + 1 < messages.length ? messages[i + 1] : null;
          return Column(
            children: [
              if (older == null || !_sameDay(older.at, m.at)) _DayLabel(m.at),
              _Bubble(
                m,
                selected: selected.contains(m.messageId),
                onLongPress: () => onLongPress(m),
                onTap: onTap == null ? null : () => onTap!(m),
              ),
            ],
          );
        },
      ),
    );
  }

  static bool _sameDay(DateTime a, DateTime b) {
    final x = a.toLocal(), y = b.toLocal();
    return x.year == y.year && x.month == y.month && x.day == y.day;
  }
}

class _DayLabel extends StatelessWidget {
  const _DayLabel(this.at);

  final DateTime at;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = at.toLocal();
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(
        '${days[l.weekday - 1]} ${l.day} ${months[l.month - 1]} ${l.year}',
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble(
    this.m, {
    required this.selected,
    required this.onLongPress,
    this.onTap,
  });

  final SmsMessage m;
  final bool selected;
  final VoidCallback onLongPress;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final out = m.direction == SmsMessageDirectionEnum.outbound;
    final failed = m.status == SmsMessageStatusEnum.failed;
    final l = m.at.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    final time = '${two(l.hour)}:${two(l.minute)}';
    // Full-width, so a selected message is tinted edge to edge.
    final bubble = Align(
      alignment: out ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.78,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Column(
            crossAxisAlignment: out
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: out ? scheme.primary : scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 9,
                  ),
                  child: Text(
                    m.text,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: out ? scheme.onPrimary : scheme.onSurface,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 2, left: 6, right: 6),
                child: Text(
                  failed ? '$time · Not delivered' : time,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: failed ? scheme.error : scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: onLongPress,
      onTap: onTap,
      child: ColoredBox(
        color: selected
            ? scheme.primary.withValues(alpha: 0.12)
            : Colors.transparent,
        child: bubble,
      ),
    );
  }
}
