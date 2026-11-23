import 'dart:typed_data';

import 'package:vouch/api/device_signer.dart';
import 'package:vouch/keys/device_key.dart';

/// A DeviceKeyStore backed by software keys, so tests can verify what the
/// server would verify. Records prompts and can refuse to sign.
class FakeKeys extends DeviceKeyStore {
  FakeKeys({
    this.biometrics = BiometricStatus.available,
    this.cancelProof = false,
  });

  final BiometricStatus biometrics;
  final bool cancelProof;
  final signers = <String, SoftwareSigner>{};
  final challenges = <String, Uint8List>{};
  final policies = <String, bool>{};
  final prompts = <PromptText>[];

  @override
  Future<BiometricStatus> biometricStatus() async => biometrics;

  @override
  Future<GeneratedKey> generate({
    required String alias,
    required Uint8List challenge,
    required bool requireUserAuth,
  }) async {
    final s = SoftwareSigner.generate();
    signers[alias] = s;
    challenges[alias] = challenge;
    policies[alias] = requireUserAuth;
    return GeneratedKey(
      publicKeySpki: await s.publicKeySpki(),
      attestationChain: [
        Uint8List.fromList([1, 2, 3]),
        Uint8List.fromList([4, 5]),
      ],
      strongBox: false,
      userAuthRequired: requireUserAuth,
    );
  }

  @override
  Future<bool> exists(String alias) async => signers.containsKey(alias);

  @override
  Future<void> delete(String alias) async => signers.remove(alias);

  @override
  Future<Uint8List> publicKeySpki(String alias) =>
      signers[alias]!.publicKeySpki();

  @override
  Future<Uint8List> sign({
    required String alias,
    required Uint8List message,
    required PromptText prompt,
  }) async {
    if (policies[alias] == true) {
      prompts.add(prompt);
      if (cancelProof) {
        throw DeviceKeyException(DeviceKeyError.cancelled, 'cancelled');
      }
    }
    // As the platform channel does when the key is gone.
    final signer = signers[alias];
    if (signer == null) {
      throw DeviceKeyException(
        DeviceKeyError.noKey,
        'No key with alias $alias',
        code: 'no_key',
      );
    }
    return signer.signDer(message);
  }
}
