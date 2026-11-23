//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of vouch_api;

class PairResponse {
  /// Returns a new [PairResponse] instance.
  PairResponse({
    required this.deviceId,
    required this.serverName,
    required this.policy,
    required this.userAuthBound,
    this.pushEnabled,
  });

  String deviceId;

  String serverName;

  Policy policy;

  /// What the server knows about whether the decision key needs a fingerprint, face or PIN for every use.
  PairResponseUserAuthBoundEnum userAuthBound;

  /// False when this phone is sent no push notifications: this server sends none (it has no Firebase service account), or the phone gave no push token (an app built with no Firebase config). The app then shows requests only when it is opened. Absent on servers older than this field: treat as true.
  ///
  /// Please note: This property should have been non-nullable! Since the specification file
  /// does not include a default value (using the "default:" property), however, the generated
  /// source code must fall back to having a nullable type.
  /// Consider adding a "default:" property in the specification file to hide this note.
  ///
  bool? pushEnabled;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PairResponse &&
          other.deviceId == deviceId &&
          other.serverName == serverName &&
          other.policy == policy &&
          other.userAuthBound == userAuthBound &&
          other.pushEnabled == pushEnabled;

  @override
  int get hashCode =>
      // ignore: unnecessary_parenthesis
      (deviceId.hashCode) +
      (serverName.hashCode) +
      (policy.hashCode) +
      (userAuthBound.hashCode) +
      (pushEnabled == null ? 0 : pushEnabled!.hashCode);

  @override
  String toString() =>
      'PairResponse[deviceId=$deviceId, serverName=$serverName, policy=$policy, userAuthBound=$userAuthBound, pushEnabled=$pushEnabled]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    json[r'device_id'] = this.deviceId;
    json[r'server_name'] = this.serverName;
    json[r'policy'] = this.policy;
    json[r'user_auth_bound'] = this.userAuthBound;
    if (this.pushEnabled != null) {
      json[r'push_enabled'] = this.pushEnabled;
    } else {
      json[r'push_enabled'] = null;
    }
    return json;
  }

  /// Returns a new [PairResponse] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static PairResponse? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'device_id'),
            'Required key "PairResponse[device_id]" is missing from JSON.');
        assert(json[r'device_id'] != null,
            'Required key "PairResponse[device_id]" has a null value in JSON.');
        assert(json.containsKey(r'server_name'),
            'Required key "PairResponse[server_name]" is missing from JSON.');
        assert(json[r'server_name'] != null,
            'Required key "PairResponse[server_name]" has a null value in JSON.');
        assert(json.containsKey(r'policy'),
            'Required key "PairResponse[policy]" is missing from JSON.');
        assert(json[r'policy'] != null,
            'Required key "PairResponse[policy]" has a null value in JSON.');
        assert(json.containsKey(r'user_auth_bound'),
            'Required key "PairResponse[user_auth_bound]" is missing from JSON.');
        assert(json[r'user_auth_bound'] != null,
            'Required key "PairResponse[user_auth_bound]" has a null value in JSON.');
        return true;
      }());

      return PairResponse(
        deviceId: mapValueOfType<String>(json, r'device_id')!,
        serverName: mapValueOfType<String>(json, r'server_name')!,
        policy: Policy.fromJson(json[r'policy'])!,
        userAuthBound:
            PairResponseUserAuthBoundEnum.fromJson(json[r'user_auth_bound'])!,
        pushEnabled: mapValueOfType<bool>(json, r'push_enabled'),
      );
    }
    return null;
  }

  static List<PairResponse> listFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final result = <PairResponse>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = PairResponse.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, PairResponse> mapFromJson(dynamic json) {
    final map = <String, PairResponse>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = PairResponse.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of PairResponse-objects as value to a dart map
  static Map<String, List<PairResponse>> mapListFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final map = <String, List<PairResponse>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = PairResponse.listFromJson(
          entry.value,
          growable: growable,
        );
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'device_id',
    'server_name',
    'policy',
    'user_auth_bound',
  };
}

/// What the server knows about whether the decision key needs a fingerprint, face or PIN for every use.
enum PairResponseUserAuthBoundEnum {
  attested._(r'attested'),
  clientAsserted._(r'client_asserted'),
  none._(r'none'),
  ;

  /// Instantiate a new enum with the provided value.
  const PairResponseUserAuthBoundEnum._(this._value);

  /// The underlying value of this enum member.
  final String _value;

  @override
  String toString() => _value;

  /// Encodes this enum as a value suitable for JSON.
  String toJson() => _value;

  /// Returns the instance of [PairResponseUserAuthBoundEnum] that was successfully decoded
  /// from the passed [value] on success, null otherwise.
  static PairResponseUserAuthBoundEnum? fromJson(dynamic value) =>
      PairResponseUserAuthBoundEnumTypeTransformer().decode(value);

  /// Returns a [List] containing instances of [PairResponseUserAuthBoundEnum]
  /// that were successfully decoded from the passed [JSON][json].
  static List<PairResponseUserAuthBoundEnum> listFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final result = <PairResponseUserAuthBoundEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = PairResponseUserAuthBoundEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

/// Transformation class that can [encode] an instance of [PairResponseUserAuthBoundEnum] to String,
/// and [decode] dynamic data back to [PairResponseUserAuthBoundEnum].
class PairResponseUserAuthBoundEnumTypeTransformer {
  factory PairResponseUserAuthBoundEnumTypeTransformer() =>
      _instance ??= const PairResponseUserAuthBoundEnumTypeTransformer._();

  const PairResponseUserAuthBoundEnumTypeTransformer._();

  String encode(PairResponseUserAuthBoundEnum data) => data._value;

  /// Returns the instance of [PairResponseUserAuthBoundEnum] that was successfully decoded
  /// from the passed [data] value on success, null otherwise.
  ///
  /// If [allowNull] is true and the [dynamic value][data] cannot be decoded successfully,
  /// then null is returned. However, if [allowNull] is false and the [dynamic value][data]
  /// cannot be decoded successfully, then an [UnimplementedError] is thrown.
  ///
  /// The [allowNull] is very handy when an API changes and a new enum value is added or removed,
  /// and users are still using an old app with the old code.
  PairResponseUserAuthBoundEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is PairResponseUserAuthBoundEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'attested':
          return PairResponseUserAuthBoundEnum.attested;
        case r'client_asserted':
          return PairResponseUserAuthBoundEnum.clientAsserted;
        case r'none':
          return PairResponseUserAuthBoundEnum.none;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  /// The singleton instance of this transformer.
  static PairResponseUserAuthBoundEnumTypeTransformer? _instance;
}
