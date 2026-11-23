import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/vouch_api_client.dart';
import '../../platform/biometry.dart';
import '../../sms/contact_picker.dart';
import '../../sms/contact_service.dart';
import '../../sms/phone_format.dart';

/// Who the agent may text. Removing someone takes Face ID and stops
/// the agent's next text to them; their history stays.
class ContactsScreen extends ConsumerStatefulWidget {
  const ContactsScreen({super.key});

  @override
  ConsumerState<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends ConsumerState<ContactsScreen> {
  /// The number being removed right now, to show progress on its row.
  String? _removing;

  Future<void> _remove(SmsContact c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove ${c.name}?'),
        content: Text(
          'Your agent will no longer be able to text '
          '${formatPhone(c.phone)}. Your message history stays.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Remove with ${Biometry.name}'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final service = ref.read(smsContactServiceProvider);
    if (service == null) return;
    setState(() => _removing = c.phone);
    final result = await service.remove(c);
    if (!mounted) return;
    setState(() => _removing = null);
    switch (result) {
      case ContactChanged():
        ref.invalidate(smsContactsProvider);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('${c.name} removed')));
      case ContactChangeFailed(:final message):
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      case ContactChangeCancelled():
        break;
    }
  }

  bool _adding = false;

  /// Picker, then a chance to fix the name, then Face ID and the signed add.
  Future<void> _add() async {
    final picked = await ref.read(contactPickerProvider).pick();
    if (picked == null || !mounted) return;
    final name = await showDialog<String>(
      context: context,
      builder: (context) => _ConfirmAdd(picked: picked),
    );
    if (name == null || !mounted) return;
    final service = ref.read(smsContactServiceProvider);
    if (service == null) return;
    setState(() => _adding = true);
    final result = await service.add(name: name, phone: picked.phone);
    if (!mounted) return;
    setState(() => _adding = false);
    switch (result) {
      case ContactChanged():
        ref.invalidate(smsContactsProvider);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$name added')));
      case ContactChangeFailed(:final message):
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      case ContactChangeCancelled():
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final contacts = ref.watch(smsContactsProvider);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Permitted contacts')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _adding || _removing != null ? null : _add,
        icon: _adding
            ? const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.person_add_alt_1),
        label: const Text('Add'),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => ref.refresh(smsContactsProvider.future),
          child: switch (contacts) {
            AsyncData(value: final list) => ListView(
              // Room for the Add button over the last row.
              padding: const EdgeInsets.only(bottom: 96),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text(
                    'Your agent can text only these people.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                if (list.isEmpty) const ListTile(title: Text('Nobody yet.')),
                for (final c in list)
                  ListTile(
                    leading: CircleAvatar(
                      child: Text(c.name.characters.first.toUpperCase()),
                    ),
                    title: Text(c.name),
                    subtitle: Text(
                      '${formatPhone(c.phone)} · ${_origin(c.addedBy)}',
                    ),
                    trailing: _removing == c.phone
                        ? const SizedBox.square(
                            dimension: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : IconButton(
                            tooltip: 'Remove ${c.name}',
                            icon: const Icon(Icons.person_remove_outlined),
                            onPressed: _removing == null
                                ? () => _remove(c)
                                : null,
                          ),
                  ),
              ],
            ),
            AsyncError() => ListView(
              children: const [
                ListTile(
                  leading: Icon(Icons.cloud_off),
                  title: Text("Couldn't load contacts"),
                  subtitle: Text('Pull down to try again.'),
                ),
              ],
            ),
            _ => const Center(child: CircularProgressIndicator()),
          },
        ),
      ),
    );
  }

  static String _origin(SmsContactAddedByEnum by) => switch (by) {
    SmsContactAddedByEnum.owner => 'added by you',
    SmsContactAddedByEnum.agentRequest => 'approved request',
    _ => 'imported',
  };
}

/// The picked number, and the name the agent will know them by (prefilled
/// from Contacts, editable). Returns the name, or null to stop.
class _ConfirmAdd extends StatefulWidget {
  const _ConfirmAdd({required this.picked});

  final PickedContact picked;

  @override
  State<_ConfirmAdd> createState() => _ConfirmAddState();
}

class _ConfirmAddState extends State<_ConfirmAdd> {
  late final _name = TextEditingController(text: widget.picked.name.trim());

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final name = _name.text.trim();
    return AlertDialog(
      title: const Text('Let your agent text'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.picked.phone),
          const SizedBox(height: 12),
          TextField(
            controller: _name,
            maxLength: 64,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Name'),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: name.isEmpty ? null : () => Navigator.pop(context, name),
          child: Text('Add with ${Biometry.name}'),
        ),
      ],
    );
  }
}
