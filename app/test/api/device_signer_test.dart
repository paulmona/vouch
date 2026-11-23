import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vouch/api/canonical.dart';
import 'package:vouch/api/device_signer.dart';

import 'test_vectors.dart';

void main() {
  final vectors = TestVectors.load();
  final spki = Canonical.base64UrlDecode(vectors.publicKeySpkiB64url);
  final signer = SoftwareSigner.fromPkcs8Pem(vectors.privateKeyPkcs8Pem);
  final verifier = EcdsaVerifier.fromSpki(spki);

  test(
    'the PKCS#8 test key derives the SPKI public key in the vectors',
    () async {
      expect(await signer.publicKeySpki(), spki);
    },
  );

  group('reference signatures verify against the reference key', () {
    for (final c in vectors.cases) {
      test(c.name, () {
        final msg = Uint8List.fromList(c.canonical.codeUnits);
        final sig = Canonical.base64UrlDecode(c.signatureB64url);
        expect(verifier.verify(msg, sig), isTrue);
      });
    }
  });

  group('our signatures verify against the reference key', () {
    for (final c in vectors.cases) {
      test(c.name, () async {
        final msg = Uint8List.fromList(c.canonical.codeUnits);
        final sig = await signer.signDer(msg);
        expect(verifier.verify(msg, sig), isTrue);
        // DER: SEQUENCE of two INTEGERs, 70 to 72 bytes for P-256.
        expect(sig[0], 0x30);
        expect(sig.length, inInclusiveRange(70, 72));
      });
    }
  });

  test('a tampered canonical string does not verify', () async {
    final c = vectors.cases.first;
    final sig = await signer.signDer(Uint8List.fromList(c.canonical.codeUnits));
    // Flip the nonce (last line); the body hash is what binds the decision.
    final tampered = '${c.canonical.substring(0, c.canonical.length - 1)}X';
    expect(tampered, isNot(c.canonical));
    expect(
      verifier.verify(Uint8List.fromList(tampered.codeUnits), sig),
      isFalse,
    );
  });

  test('a generated key signs and verifies with its own SPKI', () async {
    final fresh = SoftwareSigner.generate();
    final v = EcdsaVerifier.fromSpki(await fresh.publicKeySpki());
    final msg = Uint8List.fromList('hello'.codeUnits);
    expect(v.verify(msg, await fresh.signDer(msg)), isTrue);
    expect(verifier.verify(msg, await fresh.signDer(msg)), isFalse);
  });

  test('DER round trip', () {
    final r = BigInt.parse('ff' * 32, radix: 16) >> 1;
    final s = BigInt.from(1);
    expect(EcdsaDer.decode(EcdsaDer.encode(r, s)), (r, s));
  });
}
