//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of vouch_api;

class Error {
  /// Returns a new [Error] instance.
  Error({
    required this.code,
    required this.message,
    this.serverTime,
  });

  ErrorCodeEnum code;

  /// Plain English, safe to show to the user.
  String message;

  /// Present on clock_skew.
  ///
  /// Please note: This property should have been non-nullable! Since the specification file
  /// does not include a default value (using the "default:" property), however, the generated
  /// source code must fall back to having a nullable type.
  /// Consider adding a "default:" property in the specification file to hide this note.
  ///
  DateTime? serverTime;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Error &&
          other.code == code &&
          other.message == message &&
          other.serverTime == serverTime;

  @override
  int get hashCode =>
      // ignore: unnecessary_parenthesis
      (code.hashCode) +
      (message.hashCode) +
      (serverTime == null ? 0 : serverTime!.hashCode);

  @override
  String toString() =>
      'Error[code=$code, message=$message, serverTime=$serverTime]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    json[r'code'] = this.code;
    json[r'message'] = this.message;
    if (this.serverTime != null) {
      json[r'server_time'] = this.serverTime!.toUtc().toIso8601String();
    } else {
      json[r'server_time'] = null;
    }
    return json;
  }

  /// Returns a new [Error] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static Error? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'code'),
            'Required key "Error[code]" is missing from JSON.');
        assert(json[r'code'] != null,
            'Required key "Error[code]" has a null value in JSON.');
        assert(json.containsKey(r'message'),
            'Required key "Error[message]" is missing from JSON.');
        assert(json[r'message'] != null,
            'Required key "Error[message]" has a null value in JSON.');
        return true;
      }());

      return Error(
        code: ErrorCodeEnum.fromJson(json[r'code'])!,
        message: mapValueOfType<String>(json, r'message')!,
        serverTime: mapDateTime(json, r'server_time', r''),
      );
    }
    return null;
  }

  static List<Error> listFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final result = <Error>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = Error.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, Error> mapFromJson(dynamic json) {
    final map = <String, Error>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = Error.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of Error-objects as value to a dart map
  static Map<String, List<Error>> mapListFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final map = <String, List<Error>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = Error.listFromJson(
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

enum ErrorCodeEnum {
  badRequest._(r'bad_request'),
  badSignature._(r'bad_signature'),
  clockSkew._(r'clock_skew'),
  replayedNonce._(r'replayed_nonce'),
  unknownDevice._(r'unknown_device'),
  invalidSetupToken._(r'invalid_setup_token'),
  attestationFailed._(r'attestation_failed'),
  policyRequiresUserAuth._(r'policy_requires_user_auth'),
  notFound._(r'not_found'),
  alreadyDecided._(r'already_decided'),
  expired._(r'expired'),
  decisionNotAllowed._(r'decision_not_allowed'),
  rateLimited._(r'rate_limited'),
  ;

  /// Instantiate a new enum with the provided value.
  const ErrorCodeEnum._(this._value);

  /// The underlying value of this enum member.
  final String _value;

  @override
  String toString() => _value;

  /// Encodes this enum as a value suitable for JSON.
  String toJson() => _value;

  /// Returns the instance of [ErrorCodeEnum] that was successfully decoded
  /// from the passed [value] on success, null otherwise.
  static ErrorCodeEnum? fromJson(dynamic value) =>
      ErrorCodeEnumTypeTransformer().decode(value);

  /// Returns a [List] containing instances of [ErrorCodeEnum]
  /// that were successfully decoded from the passed [JSON][json].
  static List<ErrorCodeEnum> listFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final result = <ErrorCodeEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = ErrorCodeEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

/// Transformation class that can [encode] an instance of [ErrorCodeEnum] to String,
/// and [decode] dynamic data back to [ErrorCodeEnum].
class ErrorCodeEnumTypeTransformer {
  factory ErrorCodeEnumTypeTransformer() =>
      _instance ??= const ErrorCodeEnumTypeTransformer._();

  const ErrorCodeEnumTypeTransformer._();

  String encode(ErrorCodeEnum data) => data._value;

  /// Returns the instance of [ErrorCodeEnum] that was successfully decoded
  /// from the passed [data] value on success, null otherwise.
  ///
  /// If [allowNull] is true and the [dynamic value][data] cannot be decoded successfully,
  /// then null is returned. However, if [allowNull] is false and the [dynamic value][data]
  /// cannot be decoded successfully, then an [UnimplementedError] is thrown.
  ///
  /// The [allowNull] is very handy when an API changes and a new enum value is added or removed,
  /// and users are still using an old app with the old code.
  ErrorCodeEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is ErrorCodeEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'bad_request':
          return ErrorCodeEnum.badRequest;
        case r'bad_signature':
          return ErrorCodeEnum.badSignature;
        case r'clock_skew':
          return ErrorCodeEnum.clockSkew;
        case r'replayed_nonce':
          return ErrorCodeEnum.replayedNonce;
        case r'unknown_device':
          return ErrorCodeEnum.unknownDevice;
        case r'invalid_setup_token':
          return ErrorCodeEnum.invalidSetupToken;
        case r'attestation_failed':
          return ErrorCodeEnum.attestationFailed;
        case r'policy_requires_user_auth':
          return ErrorCodeEnum.policyRequiresUserAuth;
        case r'not_found':
          return ErrorCodeEnum.notFound;
        case r'already_decided':
          return ErrorCodeEnum.alreadyDecided;
        case r'expired':
          return ErrorCodeEnum.expired;
        case r'decision_not_allowed':
          return ErrorCodeEnum.decisionNotAllowed;
        case r'rate_limited':
          return ErrorCodeEnum.rateLimited;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  /// The singleton instance of this transformer.
  static ErrorCodeEnumTypeTransformer? _instance;
}
