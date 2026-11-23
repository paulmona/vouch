import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/asn1.dart';
import 'package:pointycastle/export.dart';

/// Signs the canonical string with the device's P-256 key.
///
/// The real signer lives in the Android Keystore behind a platform
/// channel and needs a fingerprint for every call. [SoftwareSigner] is a
/// pure-Dart stand-in for tests and for the mock-server phase.
abstract class DeviceSigner {
  /// ECDSA P-256 / SHA-256 over [message], DER encoded.
  Future<Uint8List> signDer(Uint8List message);

  /// The public key as SubjectPublicKeyInfo DER.
  Future<Uint8List> publicKeySpki();
}

/// P-256 ECDSA in software (pointycastle). Never used for a real pairing.
class SoftwareSigner implements DeviceSigner {
  SoftwareSigner(this._privateKey, this._publicKey);

  /// A fresh random key, for tests and the mock-server phase.
  factory SoftwareSigner.generate() {
    final gen = ECKeyGenerator()
      ..init(
        ParametersWithRandom(
          ECKeyGeneratorParameters(_domain),
          _fortunaSeededFromOs(),
        ),
      );
    final pair = gen.generateKeyPair();
    return SoftwareSigner(pair.privateKey, pair.publicKey);
  }

  /// From a PKCS#8 PEM (`-----BEGIN PRIVATE KEY-----`), as in the contract's
  /// test vectors.
  factory SoftwareSigner.fromPkcs8Pem(String pem) {
    final der = _pemBody(pem);
    // PrivateKeyInfo ::= SEQUENCE { version, AlgorithmIdentifier, OCTET STRING }
    final info = ASN1Parser(der).nextObject() as ASN1Sequence;
    final ecKeyDer = (info.elements![2] as ASN1OctetString).octets!;
    // ECPrivateKey ::= SEQUENCE { version 1, privateKey OCTET STRING, ... }
    final ecKey = ASN1Parser(ecKeyDer).nextObject() as ASN1Sequence;
    final scalar = (ecKey.elements![1] as ASN1OctetString).octets!;
    final d = _bytesToBigInt(scalar);
    final q = _domain.G * d;
    return SoftwareSigner(ECPrivateKey(d, _domain), ECPublicKey(q, _domain));
  }

  final ECPrivateKey _privateKey;
  final ECPublicKey _publicKey;

  @override
  Future<Uint8List> signDer(Uint8List message) async {
    // RFC 6979 deterministic nonces: no RNG failure can leak the key.
    final signer = ECDSASigner(SHA256Digest(), HMac(SHA256Digest(), 64))
      ..init(true, PrivateKeyParameter<ECPrivateKey>(_privateKey));
    final sig = signer.generateSignature(message) as ECSignature;
    return EcdsaDer.encode(sig.r, sig.s);
  }

  @override
  Future<Uint8List> publicKeySpki() async =>
      Spki.encode(_publicKey.Q!.getEncoded(false));
}

/// Verifies DER signatures against an SPKI public key. The tests use it to
/// prove our signatures check out against the contract's reference key.
class EcdsaVerifier {
  EcdsaVerifier(this._publicKey);

  factory EcdsaVerifier.fromSpki(Uint8List spkiDer) {
    final point = Spki.decodePoint(spkiDer);
    return EcdsaVerifier(
      ECPublicKey(_domain.curve.decodePoint(point), _domain),
    );
  }

  final ECPublicKey _publicKey;

  bool verify(Uint8List message, Uint8List derSignature) {
    final (r, s) = EcdsaDer.decode(derSignature);
    final verifier = ECDSASigner(SHA256Digest())
      ..init(false, PublicKeyParameter<ECPublicKey>(_publicKey));
    return verifier.verifySignature(message, ECSignature(r, s));
  }
}

/// `ECDSA-Sig-Value ::= SEQUENCE { r INTEGER, s INTEGER }`.
abstract final class EcdsaDer {
  static Uint8List encode(BigInt r, BigInt s) =>
      ASN1Sequence(elements: [ASN1Integer(r), ASN1Integer(s)]).encode();

  static (BigInt, BigInt) decode(Uint8List der) {
    final seq = ASN1Parser(der).nextObject() as ASN1Sequence;
    final r = (seq.elements![0] as ASN1Integer).integer!;
    final s = (seq.elements![1] as ASN1Integer).integer!;
    return (r, s);
  }
}

/// SubjectPublicKeyInfo for an uncompressed P-256 point.
abstract final class Spki {
  // AlgorithmIdentifier: id-ecPublicKey (1.2.840.10045.2.1), prime256v1
  // (1.2.840.10045.3.1.7). Fixed bytes; no need to build them with ASN.1.
  static final _algorithm = Uint8List.fromList([
    0x30, 0x13, //
    0x06, 0x07, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02, 0x01, //
    0x06, 0x08, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07, //
  ]);

  static Uint8List encode(Uint8List uncompressedPoint) {
    final seq = ASN1Sequence(
      elements: [
        ASN1Parser(_algorithm).nextObject(),
        ASN1BitString(stringValues: uncompressedPoint),
      ],
    );
    return seq.encode();
  }

  /// The uncompressed point bytes (`04 || X || Y`) from an SPKI.
  static Uint8List decodePoint(Uint8List spkiDer) {
    final seq = ASN1Parser(spkiDer).nextObject() as ASN1Sequence;
    final bits = seq.elements![1] as ASN1BitString;
    return Uint8List.fromList(bits.stringValues!);
  }
}

final ECDomainParameters _domain = ECCurve_secp256r1();

Uint8List _pemBody(String pem) {
  final b64 = pem
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty && !l.startsWith('-----'))
      .join();
  return Uint8List.fromList(base64.decode(b64));
}

BigInt _bytesToBigInt(Uint8List bytes) {
  var result = BigInt.zero;
  for (final b in bytes) {
    result = (result << 8) | BigInt.from(b);
  }
  return result;
}

/// pointycastle's key generator wants its own [SecureRandom]; seed it from
/// the OS CSPRNG.
SecureRandom _fortunaSeededFromOs() {
  final os = Random.secure();
  final seed = Uint8List.fromList(
    List<int>.generate(32, (_) => os.nextInt(256)),
  );
  return FortunaRandom()..seed(KeyParameter(seed));
}
