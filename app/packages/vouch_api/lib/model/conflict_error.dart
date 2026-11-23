//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of vouch_api;

class ConflictError {
  /// Returns a new [ConflictError] instance.
  ConflictError({
    required this.code,
    required this.message,
    required this.request,
  });

  ConflictErrorCodeEnum code;

  /// Plain English, safe to show to the user.
  String message;

  ApprovalRequest request;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConflictError &&
          other.code == code &&
          other.message == message &&
          other.request == request;

  @override
  int get hashCode =>
      // ignore: unnecessary_parenthesis
      (code.hashCode) + (message.hashCode) + (request.hashCode);

  @override
  String toString() =>
      'ConflictError[code=$code, message=$message, request=$request]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    json[r'code'] = this.code;
    json[r'message'] = this.message;
    json[r'request'] = this.request;
    return json;
  }

  /// Returns a new [ConflictError] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static ConflictError? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'code'),
            'Required key "ConflictError[code]" is missing from JSON.');
        assert(json[r'code'] != null,
            'Required key "ConflictError[code]" has a null value in JSON.');
        assert(json.containsKey(r'message'),
            'Required key "ConflictError[message]" is missing from JSON.');
        assert(json[r'message'] != null,
            'Required key "ConflictError[message]" has a null value in JSON.');
        assert(json.containsKey(r'request'),
            'Required key "ConflictError[request]" is missing from JSON.');
        assert(json[r'request'] != null,
            'Required key "ConflictError[request]" has a null value in JSON.');
        return true;
      }());

      return ConflictError(
        code: ConflictErrorCodeEnum.fromJson(json[r'code'])!,
        message: mapValueOfType<String>(json, r'message')!,
        request: ApprovalRequest.fromJson(json[r'request'])!,
      );
    }
    return null;
  }

  static List<ConflictError> listFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final result = <ConflictError>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = ConflictError.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, ConflictError> mapFromJson(dynamic json) {
    final map = <String, ConflictError>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = ConflictError.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of ConflictError-objects as value to a dart map
  static Map<String, List<ConflictError>> mapListFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final map = <String, List<ConflictError>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = ConflictError.listFromJson(
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
    'request',
  };
}

enum ConflictErrorCodeEnum {
  alreadyDecided._(r'already_decided'),
  expired._(r'expired'),
  shownMismatch._(r'shown_mismatch'),
  ;

  /// Instantiate a new enum with the provided value.
  const ConflictErrorCodeEnum._(this._value);

  /// The underlying value of this enum member.
  final String _value;

  @override
  String toString() => _value;

  /// Encodes this enum as a value suitable for JSON.
  String toJson() => _value;

  /// Returns the instance of [ConflictErrorCodeEnum] that was successfully decoded
  /// from the passed [value] on success, null otherwise.
  static ConflictErrorCodeEnum? fromJson(dynamic value) =>
      ConflictErrorCodeEnumTypeTransformer().decode(value);

  /// Returns a [List] containing instances of [ConflictErrorCodeEnum]
  /// that were successfully decoded from the passed [JSON][json].
  static List<ConflictErrorCodeEnum> listFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final result = <ConflictErrorCodeEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = ConflictErrorCodeEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

/// Transformation class that can [encode] an instance of [ConflictErrorCodeEnum] to String,
/// and [decode] dynamic data back to [ConflictErrorCodeEnum].
class ConflictErrorCodeEnumTypeTransformer {
  factory ConflictErrorCodeEnumTypeTransformer() =>
      _instance ??= const ConflictErrorCodeEnumTypeTransformer._();

  const ConflictErrorCodeEnumTypeTransformer._();

  String encode(ConflictErrorCodeEnum data) => data._value;

  /// Returns the instance of [ConflictErrorCodeEnum] that was successfully decoded
  /// from the passed [data] value on success, null otherwise.
  ///
  /// If [allowNull] is true and the [dynamic value][data] cannot be decoded successfully,
  /// then null is returned. However, if [allowNull] is false and the [dynamic value][data]
  /// cannot be decoded successfully, then an [UnimplementedError] is thrown.
  ///
  /// The [allowNull] is very handy when an API changes and a new enum value is added or removed,
  /// and users are still using an old app with the old code.
  ConflictErrorCodeEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is ConflictErrorCodeEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'already_decided':
          return ConflictErrorCodeEnum.alreadyDecided;
        case r'expired':
          return ConflictErrorCodeEnum.expired;
        case r'shown_mismatch':
          return ConflictErrorCodeEnum.shownMismatch;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  /// The singleton instance of this transformer.
  static ConflictErrorCodeEnumTypeTransformer? _instance;
}
