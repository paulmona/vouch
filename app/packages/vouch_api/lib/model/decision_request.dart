//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of vouch_api;

class DecisionRequest {
  /// Returns a new [DecisionRequest] instance.
  DecisionRequest({
    required this.decision,
    required this.shownDigest,
  });

  DecisionRequestDecisionEnum decision;

  /// Lower-case hex SHA-256 of what the app displayed for this request, so the signed decision is bound to the details the owner saw and not only to the request id. Compute it from the values rendered on screen, not from a new fetch. The digest is over the UTF-8 bytes of `vouch-shown-v1\\n` followed by one line per field, in this order: `request_id`, `kind`, `agent`, `site`, `login_title`, `expires_at`, `sms_phone`, `sms_name`, `sms_reason` (the last three from `sms_contact`; null when the request has none). A line is `name=<length>:<value>\\n`, where length is the value's UTF-8 byte count in decimal, or `name=-\\n` when the value is null. Values are the exact strings the server sent. Test vectors: `shown_digest` in `api/test-vectors.json`.  Required: a decision without it is refused with 400. When it does not match the server's record the answer is refused with `shown_mismatch` and the request stays pending. A request that is already decided or expired answers `already_decided` or `expired` whatever the digest.
  String shownDigest;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DecisionRequest &&
          other.decision == decision &&
          other.shownDigest == shownDigest;

  @override
  int get hashCode =>
      // ignore: unnecessary_parenthesis
      (decision.hashCode) + (shownDigest.hashCode);

  @override
  String toString() =>
      'DecisionRequest[decision=$decision, shownDigest=$shownDigest]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    json[r'decision'] = this.decision;
    json[r'shown_digest'] = this.shownDigest;
    return json;
  }

  /// Returns a new [DecisionRequest] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static DecisionRequest? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'decision'),
            'Required key "DecisionRequest[decision]" is missing from JSON.');
        assert(json[r'decision'] != null,
            'Required key "DecisionRequest[decision]" has a null value in JSON.');
        assert(json.containsKey(r'shown_digest'),
            'Required key "DecisionRequest[shown_digest]" is missing from JSON.');
        assert(json[r'shown_digest'] != null,
            'Required key "DecisionRequest[shown_digest]" has a null value in JSON.');
        return true;
      }());

      return DecisionRequest(
        decision: DecisionRequestDecisionEnum.fromJson(json[r'decision'])!,
        shownDigest: mapValueOfType<String>(json, r'shown_digest')!,
      );
    }
    return null;
  }

  static List<DecisionRequest> listFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final result = <DecisionRequest>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = DecisionRequest.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, DecisionRequest> mapFromJson(dynamic json) {
    final map = <String, DecisionRequest>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = DecisionRequest.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of DecisionRequest-objects as value to a dart map
  static Map<String, List<DecisionRequest>> mapListFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final map = <String, List<DecisionRequest>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = DecisionRequest.listFromJson(
          entry.value,
          growable: growable,
        );
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'decision',
    'shown_digest',
  };
}

enum DecisionRequestDecisionEnum {
  once._(r'once'),
  always._(r'always'),
  deny._(r'deny'),
  ;

  /// Instantiate a new enum with the provided value.
  const DecisionRequestDecisionEnum._(this._value);

  /// The underlying value of this enum member.
  final String _value;

  @override
  String toString() => _value;

  /// Encodes this enum as a value suitable for JSON.
  String toJson() => _value;

  /// Returns the instance of [DecisionRequestDecisionEnum] that was successfully decoded
  /// from the passed [value] on success, null otherwise.
  static DecisionRequestDecisionEnum? fromJson(dynamic value) =>
      DecisionRequestDecisionEnumTypeTransformer().decode(value);

  /// Returns a [List] containing instances of [DecisionRequestDecisionEnum]
  /// that were successfully decoded from the passed [JSON][json].
  static List<DecisionRequestDecisionEnum> listFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final result = <DecisionRequestDecisionEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = DecisionRequestDecisionEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

/// Transformation class that can [encode] an instance of [DecisionRequestDecisionEnum] to String,
/// and [decode] dynamic data back to [DecisionRequestDecisionEnum].
class DecisionRequestDecisionEnumTypeTransformer {
  factory DecisionRequestDecisionEnumTypeTransformer() =>
      _instance ??= const DecisionRequestDecisionEnumTypeTransformer._();

  const DecisionRequestDecisionEnumTypeTransformer._();

  String encode(DecisionRequestDecisionEnum data) => data._value;

  /// Returns the instance of [DecisionRequestDecisionEnum] that was successfully decoded
  /// from the passed [data] value on success, null otherwise.
  ///
  /// If [allowNull] is true and the [dynamic value][data] cannot be decoded successfully,
  /// then null is returned. However, if [allowNull] is false and the [dynamic value][data]
  /// cannot be decoded successfully, then an [UnimplementedError] is thrown.
  ///
  /// The [allowNull] is very handy when an API changes and a new enum value is added or removed,
  /// and users are still using an old app with the old code.
  DecisionRequestDecisionEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is DecisionRequestDecisionEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'once':
          return DecisionRequestDecisionEnum.once;
        case r'always':
          return DecisionRequestDecisionEnum.always;
        case r'deny':
          return DecisionRequestDecisionEnum.deny;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  /// The singleton instance of this transformer.
  static DecisionRequestDecisionEnumTypeTransformer? _instance;
}
