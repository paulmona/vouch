import 'dart:typed_data';

import '../api/device_signer.dart';
import 'device_key.dart';

/// A [DeviceSigner] backed by an Android Keystore key.
///
/// For the fingerprint-bound decision key, pass the [prompt] the person
/// should see; every `signDer` shows it. For the transport key (no user
/// authentication) no prompt appears and [prompt] is unused.
class KeystoreSigner implements DeviceSigner {
  KeystoreSigner({
    required this.store,
    required this.alias,
    required this.prompt,
  });

  final DeviceKeyStore store;
  final String alias;
  final PromptText prompt;

  @override
  Future<Uint8List> signDer(Uint8List message) =>
      store.sign(alias: alias, message: message, prompt: prompt);

  @override
  Future<Uint8List> publicKeySpki() => store.publicKeySpki(alias);
}
