import 'package:flutter/material.dart';

import '../api/cloudflare_access.dart';

/// The Cloudflare Access service token for one server. [server]
/// is null before pairing: the token then goes with the next pairing.
/// The secret is never shown again once saved.
class CloudflareAccessScreen extends StatefulWidget {
  const CloudflareAccessScreen({super.key, this.server, this.store});

  final Uri? server;

  /// Tests only; the app uses [CloudflareAccessStore.instance].
  final CloudflareAccessStore? store;

  @override
  State<CloudflareAccessScreen> createState() => _CloudflareAccessScreenState();
}

class _CloudflareAccessScreenState extends State<CloudflareAccessScreen> {
  late final CloudflareAccessStore _store =
      widget.store ?? CloudflareAccessStore.instance;
  final _id = TextEditingController();
  final _secret = TextEditingController();

  /// The saved token's Client ID, or null when none is set.
  String? _savedId;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _store.read(widget.server).then((t) {
      if (mounted) {
        setState(() {
          _savedId = t?.clientId;
          _loaded = true;
        });
      }
    });
  }

  @override
  void dispose() {
    _id.dispose();
    _secret.dispose();
    super.dispose();
  }

  bool get _canSave =>
      _id.text.trim().isNotEmpty && _secret.text.trim().isNotEmpty;

  Future<void> _save() async {
    final token = AccessToken(
      clientId: _id.text.trim(),
      clientSecret: _secret.text.trim(),
    );
    await _store.save(widget.server, token);
    if (!mounted) return;
    _id.clear();
    _secret.clear();
    setState(() => _savedId = token.clientId);
    _say('Service token saved');
  }

  Future<void> _remove() async {
    await _store.remove(widget.server);
    if (!mounted) return;
    setState(() => _savedId = null);
    _say('Service token removed');
  }

  void _say(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final where = switch (widget.server) {
      final s? => s.hasPort ? '${s.host}:${s.port}' : s.host,
      null => 'the server you pair with next',
    };
    return Scaffold(
      appBar: AppBar(title: const Text('Cloudflare Access')),
      body: SafeArea(
        child: !_loaded
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    'Only if your server is behind Cloudflare Access. Paste '
                    'a service token from Zero Trust, Access, Service '
                    'credentials. It is sent only to $where.',
                    style: muted,
                  ),
                  const SizedBox(height: 16),
                  if (_savedId case final id?) ...[
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.vpn_key_outlined),
                      title: const Text('Service token set'),
                      subtitle: Text('Client ID $id'),
                    ),
                    OutlinedButton(
                      onPressed: _remove,
                      child: const Text('Remove'),
                    ),
                    const SizedBox(height: 24),
                    Text('Replace it', style: theme.textTheme.titleSmall),
                    const SizedBox(height: 8),
                  ],
                  TextField(
                    controller: _id,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: const InputDecoration(labelText: 'Client ID'),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _secret,
                    obscureText: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: const InputDecoration(
                      labelText: 'Client Secret',
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _canSave ? _save : null,
                    child: const Text('Save'),
                  ),
                ],
              ),
      ),
    );
  }
}
