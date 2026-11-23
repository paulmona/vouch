//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of vouch_api;

class Device {
  /// Returns a new [Device] instance.
  Device({
    required this.deviceId,
    required this.name,
    required this.platform,
    required this.pairedAt,
    this.lastCheckinAt,
    required this.userAuthBound,
    required this.policy,
    this.rekeyRequired,
    this.pushEnabled,
  });

  String deviceId;

  String name;

  Platform platform;

  /// RFC 3339, UTC.
  DateTime pairedAt;

  /// RFC 3339, UTC.
  DateTime? lastCheckinAt;

  /// Whether the decision key is known to need a fingerprint, face or PIN for every use.
  DeviceUserAuthBoundEnum userAuthBound;

  Policy policy;

  /// True when the policy changed and this device's key no longer meets it; the app should re-pair.
  ///
  /// Please note: This property should have been non-nullable! Since the specification file
  /// does not include a default value (using the "default:" property), however, the generated
  /// source code must fall back to having a nullable type.
  /// Consider adding a "default:" property in the specification file to hide this note.
  ///
  bool? rekeyRequired;

  /// False when this server sends no push notifications (it has no Firebase service account). The app then shows requests only when it is opened. Absent on servers older than this field: treat as true.
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
      other is Device &&
          other.deviceId == deviceId &&
          other.name == name &&
          other.platform == platform &&
          other.pairedAt == pairedAt &&
          other.lastCheckinAt == lastCheckinAt &&
          other.userAuthBound == userAuthBound &&
          other.policy == policy &&
          other.rekeyRequired == rekeyRequired &&
          other.pushEnabled == pushEnabled;

  @override
  int get hashCode =>
      // ignore: unnecessary_parenthesis
      (deviceId.hashCode) +
      (name.hashCode) +
      (platform.hashCode) +
      (pairedAt.hashCode) +
      (lastCheckinAt == null ? 0 : lastCheckinAt!.hashCode) +
      (userAuthBound.hashCode) +
      (policy.hashCode) +
      (rekeyRequired == null ? 0 : rekeyRequired!.hashCode) +
      (pushEnabled == null ? 0 : pushEnabled!.hashCode);

  @override
  String toString() =>
      'Device[deviceId=$deviceId, name=$name, platform=$platform, pairedAt=$pairedAt, lastCheckinAt=$lastCheckinAt, userAuthBound=$userAuthBound, policy=$policy, rekeyRequired=$rekeyRequired, pushEnabled=$pushEnabled]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    json[r'device_id'] = this.deviceId;
    json[r'name'] = this.name;
    json[r'platform'] = this.platform;
    json[r'paired_at'] = this.pairedAt.toUtc().toIso8601String();
    if (this.lastCheckinAt != null) {
      json[r'last_checkin_at'] = this.lastCheckinAt!.toUtc().toIso8601String();
    } else {
      json[r'last_checkin_at'] = null;
    }
    json[r'user_auth_bound'] = this.userAuthBound;
    json[r'policy'] = this.policy;
    if (this.rekeyRequired != null) {
      json[r'rekey_required'] = this.rekeyRequired;
    } else {
      json[r'rekey_required'] = null;
    }
    if (this.pushEnabled != null) {
      json[r'push_enabled'] = this.pushEnabled;
    } else {
      json[r'push_enabled'] = null;
    }
    return json;
  }

  /// Returns a new [Device] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static Device? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'device_id'),
            'Required key "Device[device_id]" is missing from JSON.');
        assert(json[r'device_id'] != null,
            'Required key "Device[device_id]" has a null value in JSON.');
        assert(json.containsKey(r'name'),
            'Required key "Device[name]" is missing from JSON.');
        assert(json[r'name'] != null,
            'Required key "Device[name]" has a null value in JSON.');
        assert(json.containsKey(r'platform'),
            'Required key "Device[platform]" is missing from JSON.');
        assert(json[r'platform'] != null,
            'Required key "Device[platform]" has a null value in JSON.');
        assert(json.containsKey(r'paired_at'),
            'Required key "Device[paired_at]" is missing from JSON.');
        assert(json[r'paired_at'] != null,
            'Required key "Device[paired_at]" has a null value in JSON.');
        assert(json.containsKey(r'user_auth_bound'),
            'Required key "Device[user_auth_bound]" is missing from JSON.');
        assert(json[r'user_auth_bound'] != null,
            'Required key "Device[user_auth_bound]" has a null value in JSON.');
        assert(json.containsKey(r'policy'),
            'Required key "Device[policy]" is missing from JSON.');
        assert(json[r'policy'] != null,
            'Required key "Device[policy]" has a null value in JSON.');
        return true;
      }());

      return Device(
        deviceId: mapValueOfType<String>(json, r'device_id')!,
        name: mapValueOfType<String>(json, r'name')!,
        platform: Platform.fromJson(json[r'platform'])!,
        pairedAt: mapDateTime(json, r'paired_at', r'')!,
        lastCheckinAt: mapDateTime(json, r'last_checkin_at', r''),
        userAuthBound:
            DeviceUserAuthBoundEnum.fromJson(json[r'user_auth_bound'])!,
        policy: Policy.fromJson(json[r'policy'])!,
        rekeyRequired: mapValueOfType<bool>(json, r'rekey_required'),
        pushEnabled: mapValueOfType<bool>(json, r'push_enabled'),
      );
    }
    return null;
  }

  static List<Device> listFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final result = <Device>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = Device.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, Device> mapFromJson(dynamic json) {
    final map = <String, Device>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = Device.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of Device-objects as value to a dart map
  static Map<String, List<Device>> mapListFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final map = <String, List<Device>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = Device.listFromJson(
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
    'name',
    'platform',
    'paired_at',
    'user_auth_bound',
    'policy',
  };
}

/// Whether the decision key is known to need a fingerprint, face or PIN for every use.
enum DeviceUserAuthBoundEnum {
  attested._(r'attested'),
  clientAsserted._(r'client_asserted'),
  none._(r'none'),
  ;

  /// Instantiate a new enum with the provided value.
  const DeviceUserAuthBoundEnum._(this._value);

  /// The underlying value of this enum member.
  final String _value;

  @override
  String toString() => _value;

  /// Encodes this enum as a value suitable for JSON.
  String toJson() => _value;

  /// Returns the instance of [DeviceUserAuthBoundEnum] that was successfully decoded
  /// from the passed [value] on success, null otherwise.
  static DeviceUserAuthBoundEnum? fromJson(dynamic value) =>
      DeviceUserAuthBoundEnumTypeTransformer().decode(value);

  /// Returns a [List] containing instances of [DeviceUserAuthBoundEnum]
  /// that were successfully decoded from the passed [JSON][json].
  static List<DeviceUserAuthBoundEnum> listFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final result = <DeviceUserAuthBoundEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = DeviceUserAuthBoundEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

/// Transformation class that can [encode] an instance of [DeviceUserAuthBoundEnum] to String,
/// and [decode] dynamic data back to [DeviceUserAuthBoundEnum].
class DeviceUserAuthBoundEnumTypeTransformer {
  factory DeviceUserAuthBoundEnumTypeTransformer() =>
      _instance ??= const DeviceUserAuthBoundEnumTypeTransformer._();

  const DeviceUserAuthBoundEnumTypeTransformer._();

  String encode(DeviceUserAuthBoundEnum data) => data._value;

  /// Returns the instance of [DeviceUserAuthBoundEnum] that was successfully decoded
  /// from the passed [data] value on success, null otherwise.
  ///
  /// If [allowNull] is true and the [dynamic value][data] cannot be decoded successfully,
  /// then null is returned. However, if [allowNull] is false and the [dynamic value][data]
  /// cannot be decoded successfully, then an [UnimplementedError] is thrown.
  ///
  /// The [allowNull] is very handy when an API changes and a new enum value is added or removed,
  /// and users are still using an old app with the old code.
  DeviceUserAuthBoundEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is DeviceUserAuthBoundEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'attested':
          return DeviceUserAuthBoundEnum.attested;
        case r'client_asserted':
          return DeviceUserAuthBoundEnum.clientAsserted;
        case r'none':
          return DeviceUserAuthBoundEnum.none;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  /// The singleton instance of this transformer.
  static DeviceUserAuthBoundEnumTypeTransformer? _instance;
}
