//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of vouch_api;

class SmsError {
  /// Returns a new [SmsError] instance.
  SmsError({
    required this.code,
    required this.message,
  });

  SmsErrorCodeEnum code;

  /// Plain English, safe to show to the user.
  String message;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SmsError && other.code == code && other.message == message;

  @override
  int get hashCode =>
      // ignore: unnecessary_parenthesis
      (code.hashCode) + (message.hashCode);

  @override
  String toString() => 'SmsError[code=$code, message=$message]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    json[r'code'] = this.code;
    json[r'message'] = this.message;
    return json;
  }

  /// Returns a new [SmsError] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static SmsError? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'code'),
            'Required key "SmsError[code]" is missing from JSON.');
        assert(json[r'code'] != null,
            'Required key "SmsError[code]" has a null value in JSON.');
        assert(json.containsKey(r'message'),
            'Required key "SmsError[message]" is missing from JSON.');
        assert(json[r'message'] != null,
            'Required key "SmsError[message]" has a null value in JSON.');
        return true;
      }());

      return SmsError(
        code: SmsErrorCodeEnum.fromJson(json[r'code'])!,
        message: mapValueOfType<String>(json, r'message')!,
      );
    }
    return null;
  }

  static List<SmsError> listFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final result = <SmsError>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = SmsError.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, SmsError> mapFromJson(dynamic json) {
    final map = <String, SmsError>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = SmsError.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of SmsError-objects as value to a dart map
  static Map<String, List<SmsError>> mapListFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final map = <String, List<SmsError>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = SmsError.listFromJson(
          entry.value,
          growable: growable,
        );
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'code',
    'message',
  };
}

enum SmsErrorCodeEnum {
  invalidNumber._(r'invalid_number'),
  contactExists._(r'contact_exists'),
  policyRequiresUserAuth._(r'policy_requires_user_auth'),
  ;

  /// Instantiate a new enum with the provided value.
  const SmsErrorCodeEnum._(this._value);

  /// The underlying value of this enum member.
  final String _value;

  @override
  String toString() => _value;

  /// Encodes this enum as a value suitable for JSON.
  String toJson() => _value;

  /// Returns the instance of [SmsErrorCodeEnum] that was successfully decoded
  /// from the passed [value] on success, null otherwise.
  static SmsErrorCodeEnum? fromJson(dynamic value) =>
      SmsErrorCodeEnumTypeTransformer().decode(value);

  /// Returns a [List] containing instances of [SmsErrorCodeEnum]
  /// that were successfully decoded from the passed [JSON][json].
  static List<SmsErrorCodeEnum> listFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final result = <SmsErrorCodeEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = SmsErrorCodeEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

/// Transformation class that can [encode] an instance of [SmsErrorCodeEnum] to String,
/// and [decode] dynamic data back to [SmsErrorCodeEnum].
class SmsErrorCodeEnumTypeTransformer {
  factory SmsErrorCodeEnumTypeTransformer() =>
      _instance ??= const SmsErrorCodeEnumTypeTransformer._();

  const SmsErrorCodeEnumTypeTransformer._();

  String encode(SmsErrorCodeEnum data) => data._value;

  /// Returns the instance of [SmsErrorCodeEnum] that was successfully decoded
  /// from the passed [data] value on success, null otherwise.
  ///
  /// If [allowNull] is true and the [dynamic value][data] cannot be decoded successfully,
  /// then null is returned. However, if [allowNull] is false and the [dynamic value][data]
  /// cannot be decoded successfully, then an [UnimplementedError] is thrown.
  ///
  /// The [allowNull] is very handy when an API changes and a new enum value is added or removed,
  /// and users are still using an old app with the old code.
  SmsErrorCodeEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is SmsErrorCodeEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'invalid_number':
          return SmsErrorCodeEnum.invalidNumber;
        case r'contact_exists':
          return SmsErrorCodeEnum.contactExists;
        case r'policy_requires_user_auth':
          return SmsErrorCodeEnum.policyRequiresUserAuth;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  /// The singleton instance of this transformer.
  static SmsErrorCodeEnumTypeTransformer? _instance;
}
