//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of vouch_api;

class PairRequest {
  /// Returns a new [PairRequest] instance.
  PairRequest({
    required this.setupToken,
    required this.publicKey,
    this.attestationChain = const [],
    required this.decisionKeyProof,
    required this.transportPublicKey,
    this.transportAttestationChain = const [],
    required this.pushToken,
    required this.name,
    required this.platform,
  });

  String setupToken;

  /// The decision key. P-256 SubjectPublicKeyInfo DER, base64url without padding.
  String publicKey;

  /// The decision key's Android key attestation certificates, leaf first, each DER base64url. Empty on iOS.
  List<String> attestationChain;

  /// The decision key's signature over the UTF-8 string `vouch-pair-v1\\n` + setup_token: ECDSA P-256 / SHA-256, DER, base64url without padding.
  String decisionKeyProof;

  /// The transport key, which signs every call except decisions. P-256 SubjectPublicKeyInfo DER, base64url without padding. Must differ from public_key.
  String transportPublicKey;

  /// Optional Android attestation of the transport key (same rules as attestation_chain, no user-auth requirement). Omit or leave empty on iOS.
  List<String> transportAttestationChain;

  String pushToken;

  String name;

  Platform platform;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PairRequest &&
          other.setupToken == setupToken &&
          other.publicKey == publicKey &&
          _deepEquality.equals(other.attestationChain, attestationChain) &&
          other.decisionKeyProof == decisionKeyProof &&
          other.transportPublicKey == transportPublicKey &&
          _deepEquality.equals(
              other.transportAttestationChain, transportAttestationChain) &&
          other.pushToken == pushToken &&
          other.name == name &&
          other.platform == platform;

  @override
  int get hashCode =>
      // ignore: unnecessary_parenthesis
      (setupToken.hashCode) +
      (publicKey.hashCode) +
      (attestationChain.hashCode) +
      (decisionKeyProof.hashCode) +
      (transportPublicKey.hashCode) +
      (transportAttestationChain.hashCode) +
      (pushToken.hashCode) +
      (name.hashCode) +
      (platform.hashCode);

  @override
  String toString() =>
      'PairRequest[setupToken=$setupToken, publicKey=$publicKey, attestationChain=$attestationChain, decisionKeyProof=$decisionKeyProof, transportPublicKey=$transportPublicKey, transportAttestationChain=$transportAttestationChain, pushToken=$pushToken, name=$name, platform=$platform]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    json[r'setup_token'] = this.setupToken;
    json[r'public_key'] = this.publicKey;
    json[r'attestation_chain'] = this.attestationChain;
    json[r'decision_key_proof'] = this.decisionKeyProof;
    json[r'transport_public_key'] = this.transportPublicKey;
    json[r'transport_attestation_chain'] = this.transportAttestationChain;
    json[r'push_token'] = this.pushToken;
    json[r'name'] = this.name;
    json[r'platform'] = this.platform;
    return json;
  }

  /// Returns a new [PairRequest] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static PairRequest? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'setup_token'),
            'Required key "PairRequest[setup_token]" is missing from JSON.');
        assert(json[r'setup_token'] != null,
            'Required key "PairRequest[setup_token]" has a null value in JSON.');
        assert(json.containsKey(r'public_key'),
            'Required key "PairRequest[public_key]" is missing from JSON.');
        assert(json[r'public_key'] != null,
            'Required key "PairRequest[public_key]" has a null value in JSON.');
        assert(json.containsKey(r'attestation_chain'),
            'Required key "PairRequest[attestation_chain]" is missing from JSON.');
        assert(json[r'attestation_chain'] != null,
            'Required key "PairRequest[attestation_chain]" has a null value in JSON.');
        assert(json.containsKey(r'decision_key_proof'),
            'Required key "PairRequest[decision_key_proof]" is missing from JSON.');
        assert(json[r'decision_key_proof'] != null,
            'Required key "PairRequest[decision_key_proof]" has a null value in JSON.');
        assert(json.containsKey(r'transport_public_key'),
            'Required key "PairRequest[transport_public_key]" is missing from JSON.');
        assert(json[r'transport_public_key'] != null,
            'Required key "PairRequest[transport_public_key]" has a null value in JSON.');
        assert(json.containsKey(r'push_token'),
            'Required key "PairRequest[push_token]" is missing from JSON.');
        assert(json[r'push_token'] != null,
            'Required key "PairRequest[push_token]" has a null value in JSON.');
        assert(json.containsKey(r'name'),
            'Required key "PairRequest[name]" is missing from JSON.');
        assert(json[r'name'] != null,
            'Required key "PairRequest[name]" has a null value in JSON.');
        assert(json.containsKey(r'platform'),
            'Required key "PairRequest[platform]" is missing from JSON.');
        assert(json[r'platform'] != null,
            'Required key "PairRequest[platform]" has a null value in JSON.');
        return true;
      }());

      return PairRequest(
        setupToken: mapValueOfType<String>(json, r'setup_token')!,
        publicKey: mapValueOfType<String>(json, r'public_key')!,
        attestationChain: json[r'attestation_chain'] is Iterable
            ? (json[r'attestation_chain'] as Iterable)
                .cast<String>()
                .toList(growable: false)
            : const [],
        decisionKeyProof: mapValueOfType<String>(json, r'decision_key_proof')!,
        transportPublicKey:
            mapValueOfType<String>(json, r'transport_public_key')!,
        transportAttestationChain:
            json[r'transport_attestation_chain'] is Iterable
                ? (json[r'transport_attestation_chain'] as Iterable)
                    .cast<String>()
                    .toList(growable: false)
                : const [],
        pushToken: mapValueOfType<String>(json, r'push_token')!,
        name: mapValueOfType<String>(json, r'name')!,
        platform: Platform.fromJson(json[r'platform'])!,
      );
    }
    return null;
  }

  static List<PairRequest> listFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final result = <PairRequest>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = PairRequest.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, PairRequest> mapFromJson(dynamic json) {
    final map = <String, PairRequest>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = PairRequest.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of PairRequest-objects as value to a dart map
  static Map<String, List<PairRequest>> mapListFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final map = <String, List<PairRequest>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = PairRequest.listFromJson(
          entry.value,
          growable: growable,
        );
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'setup_token',
    'public_key',
    'attestation_chain',
    'decision_key_proof',
    'transport_public_key',
    'push_token',
    'name',
    'platform',
  };
}
