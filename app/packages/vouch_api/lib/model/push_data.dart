//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of vouch_api;

class PushData {
  /// Returns a new [PushData] instance.
  PushData({
    required this.v,
    required this.kind,
    this.requestId,
    this.heartbeatId,
    this.alertId,
  });

  PushDataVEnum v;

  PushDataKindEnum kind;

  ///
  /// Please note: This property should have been non-nullable! Since the specification file
  /// does not include a default value (using the "default:" property), however, the generated
  /// source code must fall back to having a nullable type.
  /// Consider adding a "default:" property in the specification file to hide this note.
  ///
  String? requestId;

  ///
  /// Please note: This property should have been non-nullable! Since the specification file
  /// does not include a default value (using the "default:" property), however, the generated
  /// source code must fall back to having a nullable type.
  /// Consider adding a "default:" property in the specification file to hide this note.
  ///
  String? heartbeatId;

  ///
  /// Please note: This property should have been non-nullable! Since the specification file
  /// does not include a default value (using the "default:" property), however, the generated
  /// source code must fall back to having a nullable type.
  /// Consider adding a "default:" property in the specification file to hide this note.
  ///
  String? alertId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PushData &&
          other.v == v &&
          other.kind == kind &&
          other.requestId == requestId &&
          other.heartbeatId == heartbeatId &&
          other.alertId == alertId;

  @override
  int get hashCode =>
      // ignore: unnecessary_parenthesis
      (v.hashCode) +
      (kind.hashCode) +
      (requestId == null ? 0 : requestId!.hashCode) +
      (heartbeatId == null ? 0 : heartbeatId!.hashCode) +
      (alertId == null ? 0 : alertId!.hashCode);

  @override
  String toString() =>
      'PushData[v=$v, kind=$kind, requestId=$requestId, heartbeatId=$heartbeatId, alertId=$alertId]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    json[r'v'] = this.v;
    json[r'kind'] = this.kind;
    if (this.requestId != null) {
      json[r'request_id'] = this.requestId;
    } else {
      json[r'request_id'] = null;
    }
    if (this.heartbeatId != null) {
      json[r'heartbeat_id'] = this.heartbeatId;
    } else {
      json[r'heartbeat_id'] = null;
    }
    if (this.alertId != null) {
      json[r'alert_id'] = this.alertId;
    } else {
      json[r'alert_id'] = null;
    }
    return json;
  }

  /// Returns a new [PushData] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static PushData? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'v'),
            'Required key "PushData[v]" is missing from JSON.');
        assert(json[r'v'] != null,
            'Required key "PushData[v]" has a null value in JSON.');
        assert(json.containsKey(r'kind'),
            'Required key "PushData[kind]" is missing from JSON.');
        assert(json[r'kind'] != null,
            'Required key "PushData[kind]" has a null value in JSON.');
        return true;
      }());

      return PushData(
        v: PushDataVEnum.fromJson(json[r'v'])!,
        kind: PushDataKindEnum.fromJson(json[r'kind'])!,
        requestId: mapValueOfType<String>(json, r'request_id'),
        heartbeatId: mapValueOfType<String>(json, r'heartbeat_id'),
        alertId: mapValueOfType<String>(json, r'alert_id'),
      );
    }
    return null;
  }

  static List<PushData> listFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final result = <PushData>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = PushData.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, PushData> mapFromJson(dynamic json) {
    final map = <String, PushData>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = PushData.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of PushData-objects as value to a dart map
  static Map<String, List<PushData>> mapListFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final map = <String, List<PushData>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = PushData.listFromJson(
          entry.value,
          growable: growable,
        );
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'v',
    'kind',
  };
}

enum PushDataVEnum {
  n1._(r'1'),
  ;

  /// Instantiate a new enum with the provided value.
  const PushDataVEnum._(this._value);

  /// The underlying value of this enum member.
  final String _value;

  @override
  String toString() => _value;

  /// Encodes this enum as a value suitable for JSON.
  String toJson() => _value;

  /// Returns the instance of [PushDataVEnum] that was successfully decoded
  /// from the passed [value] on success, null otherwise.
  static PushDataVEnum? fromJson(dynamic value) =>
      PushDataVEnumTypeTransformer().decode(value);

  /// Returns a [List] containing instances of [PushDataVEnum]
  /// that were successfully decoded from the passed [JSON][json].
  static List<PushDataVEnum> listFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final result = <PushDataVEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = PushDataVEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

/// Transformation class that can [encode] an instance of [PushDataVEnum] to String,
/// and [decode] dynamic data back to [PushDataVEnum].
class PushDataVEnumTypeTransformer {
  factory PushDataVEnumTypeTransformer() =>
      _instance ??= const PushDataVEnumTypeTransformer._();

  const PushDataVEnumTypeTransformer._();

  String encode(PushDataVEnum data) => data._value;

  /// Returns the instance of [PushDataVEnum] that was successfully decoded
  /// from the passed [data] value on success, null otherwise.
  ///
  /// If [allowNull] is true and the [dynamic value][data] cannot be decoded successfully,
  /// then null is returned. However, if [allowNull] is false and the [dynamic value][data]
  /// cannot be decoded successfully, then an [UnimplementedError] is thrown.
  ///
  /// The [allowNull] is very handy when an API changes and a new enum value is added or removed,
  /// and users are still using an old app with the old code.
  PushDataVEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is PushDataVEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'1':
          return PushDataVEnum.n1;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  /// The singleton instance of this transformer.
  static PushDataVEnumTypeTransformer? _instance;
}

enum PushDataKindEnum {
  request._(r'request'),
  clear._(r'clear'),
  heartbeat._(r'heartbeat'),
  alert._(r'alert'),
  smsUpdated._(r'sms_updated'),
  ;

  /// Instantiate a new enum with the provided value.
  const PushDataKindEnum._(this._value);

  /// The underlying value of this enum member.
  final String _value;

  @override
  String toString() => _value;

  /// Encodes this enum as a value suitable for JSON.
  String toJson() => _value;

  /// Returns the instance of [PushDataKindEnum] that was successfully decoded
  /// from the passed [value] on success, null otherwise.
  static PushDataKindEnum? fromJson(dynamic value) =>
      PushDataKindEnumTypeTransformer().decode(value);

  /// Returns a [List] containing instances of [PushDataKindEnum]
  /// that were successfully decoded from the passed [JSON][json].
  static List<PushDataKindEnum> listFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final result = <PushDataKindEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = PushDataKindEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

/// Transformation class that can [encode] an instance of [PushDataKindEnum] to String,
/// and [decode] dynamic data back to [PushDataKindEnum].
class PushDataKindEnumTypeTransformer {
  factory PushDataKindEnumTypeTransformer() =>
      _instance ??= const PushDataKindEnumTypeTransformer._();

  const PushDataKindEnumTypeTransformer._();

  String encode(PushDataKindEnum data) => data._value;

  /// Returns the instance of [PushDataKindEnum] that was successfully decoded
  /// from the passed [data] value on success, null otherwise.
  ///
  /// If [allowNull] is true and the [dynamic value][data] cannot be decoded successfully,
  /// then null is returned. However, if [allowNull] is false and the [dynamic value][data]
  /// cannot be decoded successfully, then an [UnimplementedError] is thrown.
  ///
  /// The [allowNull] is very handy when an API changes and a new enum value is added or removed,
  /// and users are still using an old app with the old code.
  PushDataKindEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is PushDataKindEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'request':
          return PushDataKindEnum.request;
        case r'clear':
          return PushDataKindEnum.clear;
        case r'heartbeat':
          return PushDataKindEnum.heartbeat;
        case r'alert':
          return PushDataKindEnum.alert;
        case r'sms_updated':
          return PushDataKindEnum.smsUpdated;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  /// The singleton instance of this transformer.
  static PushDataKindEnumTypeTransformer? _instance;
}
