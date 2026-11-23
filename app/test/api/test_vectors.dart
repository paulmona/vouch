import 'dart:convert';
import 'dart:io';

/// The contract's reference vectors (`api/test-vectors.json`), read straight
/// from the repo so the app can never drift from the spec silently.
class TestVectors {
  TestVectors._(this.json);

  factory TestVectors.load() {
    final file = File('../api/test-vectors.json');
    return TestVectors._(
      jsonDecode(file.readAsStringSync()) as Map<String, dynamic>,
    );
  }

  final Map<String, dynamic> json;

  String get publicKeySpkiB64url => json['public_key_spki_b64url'] as String;
  String get privateKeyPkcs8Pem => json['private_key_pkcs8_pem'] as String;

  List<VectorCase> get cases => (json['cases'] as List<dynamic>)
      .map((c) => VectorCase(c as Map<String, dynamic>))
      .toList();
}

class VectorCase {
  VectorCase(this.json);

  final Map<String, dynamic> json;

  String get name => json['name'] as String;
  String get method => json['method'] as String;
  String get target => json['target'] as String;
  String get body => json['body'] as String;
  String get timestamp => json['timestamp'] as String;
  String get nonce => json['nonce'] as String;
  String get bodySha256Hex => json['body_sha256_hex'] as String;
  String get canonical => json['canonical'] as String;
  String get signatureB64url => json['signature_b64url'] as String;
}
