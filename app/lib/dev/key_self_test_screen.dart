import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';

import '../api/canonical.dart';
import '../api/device_signer.dart';
import '../keys/device_key.dart';

/// Debug builds only: exercises the Keystore channel on a real device or
/// emulator and shows what the server would see. Also the manual check for
/// "no signature without a fingerprint": the Sign button must show the
/// system sheet, and cancelling it must produce no signature.
class KeySelfTestScreen extends StatefulWidget {
  const KeySelfTestScreen({super.key});

  @override
  State<KeySelfTestScreen> createState() => _KeySelfTestScreenState();
}

class _KeySelfTestScreenState extends State<KeySelfTestScreen> {
  final _store = DeviceKeyStore();
  final _log = <String>[];
  bool _busy = false;
  static const _alias = 'vouch.selftest';

  void _say(String s) => setState(() => _log.insert(0, s));

  Future<void> _run(String what, Future<void> Function() body) async {
    setState(() => _busy = true);
    try {
      await body();
    } on DeviceKeyException catch (e) {
      _say('$what: ${e.error.name} — ${e.message}');
    } catch (e) {
      _say('$what: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _status() => _run('status', () async {
    final s = await _store.biometricStatus();
    final exists = await _store.exists(_alias);
    _say('biometrics: ${s.name}; self-test key exists: $exists');
    if (exists) {
      final i = await _store.info(_alias);
      _say(
        'key: strongBox=${i.strongBox} userAuthRequired=${i.userAuthRequired}',
      );
    }
  });

  Future<void> _generate(bool requireUserAuth) => _run('generate', () async {
    final challenge = Uint8List.fromList(
      sha256.convert(utf8.encode('TEST-SETUP-TOKEN')).bytes,
    );
    final sw = Stopwatch()..start();
    final k = await _store.generate(
      alias: _alias,
      challenge: challenge,
      requireUserAuth: requireUserAuth,
    );
    _say(
      'generated in ${sw.elapsedMilliseconds} ms: strongBox=${k.strongBox} '
      'userAuth=${k.userAuthRequired} chain=${k.attestationChain.length} certs '
      'spki=${Canonical.base64UrlNoPad(k.publicKeySpki).substring(0, 24)}…',
    );
  });

  Future<void> _sign() => _run('sign', () async {
    final msg = Uint8List.fromList(
      utf8.encode('POST\n/v1/requests/x/decision\n…'),
    );
    final sig = await _store.sign(
      alias: _alias,
      message: msg,
      prompt: PromptText.confirmApproval(
        agent: 'Scout',
        site: 'shop.example.com',
      ),
    );
    final spki = await _store.publicKeySpki(_alias);
    final ok = EcdsaVerifier.fromSpki(spki).verify(msg, sig);
    _say('signed ${sig.length} bytes DER; verifies against SPKI: $ok');
  });

  Future<void> _delete() => _run('delete', () async {
    await _store.delete(_alias);
    _say('deleted');
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Key self-test')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: _busy ? null : _status,
                    child: const Text('Status'),
                  ),
                  FilledButton.tonal(
                    onPressed: _busy ? null : () => _generate(true),
                    child: const Text('Generate fingerprint key'),
                  ),
                  FilledButton.tonal(
                    onPressed: _busy ? null : () => _generate(false),
                    child: const Text('Generate plain key'),
                  ),
                  FilledButton(
                    onPressed: _busy ? null : _sign,
                    child: const Text('Sign'),
                  ),
                  OutlinedButton(
                    onPressed: _busy ? null : _delete,
                    child: const Text('Delete'),
                  ),
                ],
              ),
            ),
            const Divider(),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _log.length,
                itemBuilder: (_, i) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(_log[i], style: theme.textTheme.bodyMedium),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
