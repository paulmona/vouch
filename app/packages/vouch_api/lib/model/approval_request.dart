//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of vouch_api;

class ApprovalRequest {
  /// Returns a new [ApprovalRequest] instance.
  ApprovalRequest({
    required this.requestId,
    required this.kind,
    required this.agent,
    required this.site,
    this.loginTitle,
    this.smsContact,
    required this.createdAt,
    required this.expiresAt,
    required this.state,
    this.decidedAt,
    this.decidedBy,
  });

  String requestId;

  /// `sign_in`: an agent wants to use a login. `sms_contact`: an agent asks to text someone new (only when the sms module is on); details in `sms_contact`.
  ApprovalRequestKindEnum kind;

  /// Display name of the requesting agent, e.g. Research agent.
  String agent;

  /// Host the login is for (sign_in), or the E.164 number (sms_contact).
  String site;

  /// The login's title in the password manager. Never a username or password.
  String? loginTitle;

  ApprovalRequestSmsContact? smsContact;

  /// RFC 3339, UTC.
  DateTime createdAt;

  /// RFC 3339, UTC.
  DateTime expiresAt;

  ApprovalRequestStateEnum state;

  /// RFC 3339, UTC.
  DateTime? decidedAt;

  /// Who decided, from the calling device's point of view.
  ApprovalRequestDecidedByEnum? decidedBy;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ApprovalRequest &&
          other.requestId == requestId &&
          other.kind == kind &&
          other.agent == agent &&
          other.site == site &&
          other.loginTitle == loginTitle &&
          other.smsContact == smsContact &&
          other.createdAt == createdAt &&
          other.expiresAt == expiresAt &&
          other.state == state &&
          other.decidedAt == decidedAt &&
          other.decidedBy == decidedBy;

  @override
  int get hashCode =>
      // ignore: unnecessary_parenthesis
      (requestId.hashCode) +
      (kind.hashCode) +
      (agent.hashCode) +
      (site.hashCode) +
      (loginTitle == null ? 0 : loginTitle!.hashCode) +
      (smsContact == null ? 0 : smsContact!.hashCode) +
      (createdAt.hashCode) +
      (expiresAt.hashCode) +
      (state.hashCode) +
      (decidedAt == null ? 0 : decidedAt!.hashCode) +
      (decidedBy == null ? 0 : decidedBy!.hashCode);

  @override
  String toString() =>
      'ApprovalRequest[requestId=$requestId, kind=$kind, agent=$agent, site=$site, loginTitle=$loginTitle, smsContact=$smsContact, createdAt=$createdAt, expiresAt=$expiresAt, state=$state, decidedAt=$decidedAt, decidedBy=$decidedBy]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    json[r'request_id'] = this.requestId;
    json[r'kind'] = this.kind;
    json[r'agent'] = this.agent;
    json[r'site'] = this.site;
    if (this.loginTitle != null) {
      json[r'login_title'] = this.loginTitle;
    } else {
      json[r'login_title'] = null;
    }
    if (this.smsContact != null) {
      json[r'sms_contact'] = this.smsContact;
    } else {
      json[r'sms_contact'] = null;
    }
    json[r'created_at'] = this.createdAt.toUtc().toIso8601String();
    json[r'expires_at'] = this.expiresAt.toUtc().toIso8601String();
    json[r'state'] = this.state;
    if (this.decidedAt != null) {
      json[r'decided_at'] = this.decidedAt!.toUtc().toIso8601String();
    } else {
      json[r'decided_at'] = null;
    }
    if (this.decidedBy != null) {
      json[r'decided_by'] = this.decidedBy;
    } else {
      json[r'decided_by'] = null;
    }
    return json;
  }

  /// Returns a new [ApprovalRequest] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static ApprovalRequest? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'request_id'),
            'Required key "ApprovalRequest[request_id]" is missing from JSON.');
        assert(json[r'request_id'] != null,
            'Required key "ApprovalRequest[request_id]" has a null value in JSON.');
        assert(json.containsKey(r'kind'),
            'Required key "ApprovalRequest[kind]" is missing from JSON.');
        assert(json[r'kind'] != null,
            'Required key "ApprovalRequest[kind]" has a null value in JSON.');
        assert(json.containsKey(r'agent'),
            'Required key "ApprovalRequest[agent]" is missing from JSON.');
        assert(json[r'agent'] != null,
            'Required key "ApprovalRequest[agent]" has a null value in JSON.');
        assert(json.containsKey(r'site'),
            'Required key "ApprovalRequest[site]" is missing from JSON.');
        assert(json[r'site'] != null,
            'Required key "ApprovalRequest[site]" has a null value in JSON.');
        assert(json.containsKey(r'created_at'),
            'Required key "ApprovalRequest[created_at]" is missing from JSON.');
        assert(json[r'created_at'] != null,
            'Required key "ApprovalRequest[created_at]" has a null value in JSON.');
        assert(json.containsKey(r'expires_at'),
            'Required key "ApprovalRequest[expires_at]" is missing from JSON.');
        assert(json[r'expires_at'] != null,
            'Required key "ApprovalRequest[expires_at]" has a null value in JSON.');
        assert(json.containsKey(r'state'),
            'Required key "ApprovalRequest[state]" is missing from JSON.');
        assert(json[r'state'] != null,
            'Required key "ApprovalRequest[state]" has a null value in JSON.');
        return true;
      }());

      return ApprovalRequest(
        requestId: mapValueOfType<String>(json, r'request_id')!,
        kind: ApprovalRequestKindEnum.fromJson(json[r'kind'])!,
        agent: mapValueOfType<String>(json, r'agent')!,
        site: mapValueOfType<String>(json, r'site')!,
        loginTitle: mapValueOfType<String>(json, r'login_title'),
        smsContact: ApprovalRequestSmsContact.fromJson(json[r'sms_contact']),
        createdAt: mapDateTime(json, r'created_at', r'')!,
        expiresAt: mapDateTime(json, r'expires_at', r'')!,
        state: ApprovalRequestStateEnum.fromJson(json[r'state'])!,
        decidedAt: mapDateTime(json, r'decided_at', r''),
        decidedBy: ApprovalRequestDecidedByEnum.fromJson(json[r'decided_by']),
      );
    }
    return null;
  }

  static List<ApprovalRequest> listFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final result = <ApprovalRequest>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = ApprovalRequest.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, ApprovalRequest> mapFromJson(dynamic json) {
    final map = <String, ApprovalRequest>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = ApprovalRequest.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of ApprovalRequest-objects as value to a dart map
  static Map<String, List<ApprovalRequest>> mapListFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final map = <String, List<ApprovalRequest>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = ApprovalRequest.listFromJson(
          entry.value,
          growable: growable,
        );
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'request_id',
    'kind',
    'agent',
    'site',
    'created_at',
    'expires_at',
    'state',
  };
}

/// `sign_in`: an agent wants to use a login. `sms_contact`: an agent asks to text someone new (only when the sms module is on); details in `sms_contact`.
enum ApprovalRequestKindEnum {
  signIn._(r'sign_in'),
  smsContact._(r'sms_contact'),
  ;

  /// Instantiate a new enum with the provided value.
  const ApprovalRequestKindEnum._(this._value);

  /// The underlying value of this enum member.
  final String _value;

  @override
  String toString() => _value;

  /// Encodes this enum as a value suitable for JSON.
  String toJson() => _value;

  /// Returns the instance of [ApprovalRequestKindEnum] that was successfully decoded
  /// from the passed [value] on success, null otherwise.
  static ApprovalRequestKindEnum? fromJson(dynamic value) =>
      ApprovalRequestKindEnumTypeTransformer().decode(value);

  /// Returns a [List] containing instances of [ApprovalRequestKindEnum]
  /// that were successfully decoded from the passed [JSON][json].
  static List<ApprovalRequestKindEnum> listFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final result = <ApprovalRequestKindEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = ApprovalRequestKindEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

/// Transformation class that can [encode] an instance of [ApprovalRequestKindEnum] to String,
/// and [decode] dynamic data back to [ApprovalRequestKindEnum].
class ApprovalRequestKindEnumTypeTransformer {
  factory ApprovalRequestKindEnumTypeTransformer() =>
      _instance ??= const ApprovalRequestKindEnumTypeTransformer._();

  const ApprovalRequestKindEnumTypeTransformer._();

  String encode(ApprovalRequestKindEnum data) => data._value;

  /// Returns the instance of [ApprovalRequestKindEnum] that was successfully decoded
  /// from the passed [data] value on success, null otherwise.
  ///
  /// If [allowNull] is true and the [dynamic value][data] cannot be decoded successfully,
  /// then null is returned. However, if [allowNull] is false and the [dynamic value][data]
  /// cannot be decoded successfully, then an [UnimplementedError] is thrown.
  ///
  /// The [allowNull] is very handy when an API changes and a new enum value is added or removed,
  /// and users are still using an old app with the old code.
  ApprovalRequestKindEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is ApprovalRequestKindEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'sign_in':
          return ApprovalRequestKindEnum.signIn;
        case r'sms_contact':
          return ApprovalRequestKindEnum.smsContact;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  /// The singleton instance of this transformer.
  static ApprovalRequestKindEnumTypeTransformer? _instance;
}

enum ApprovalRequestStateEnum {
  pending._(r'pending'),
  once._(r'once'),
  always._(r'always'),
  deny._(r'deny'),
  timeout._(r'timeout'),
  cancelled._(r'cancelled'),
  ;

  /// Instantiate a new enum with the provided value.
  const ApprovalRequestStateEnum._(this._value);

  /// The underlying value of this enum member.
  final String _value;

  @override
  String toString() => _value;

  /// Encodes this enum as a value suitable for JSON.
  String toJson() => _value;

  /// Returns the instance of [ApprovalRequestStateEnum] that was successfully decoded
  /// from the passed [value] on success, null otherwise.
  static ApprovalRequestStateEnum? fromJson(dynamic value) =>
      ApprovalRequestStateEnumTypeTransformer().decode(value);

  /// Returns a [List] containing instances of [ApprovalRequestStateEnum]
  /// that were successfully decoded from the passed [JSON][json].
  static List<ApprovalRequestStateEnum> listFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final result = <ApprovalRequestStateEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = ApprovalRequestStateEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

/// Transformation class that can [encode] an instance of [ApprovalRequestStateEnum] to String,
/// and [decode] dynamic data back to [ApprovalRequestStateEnum].
class ApprovalRequestStateEnumTypeTransformer {
  factory ApprovalRequestStateEnumTypeTransformer() =>
      _instance ??= const ApprovalRequestStateEnumTypeTransformer._();

  const ApprovalRequestStateEnumTypeTransformer._();

  String encode(ApprovalRequestStateEnum data) => data._value;

  /// Returns the instance of [ApprovalRequestStateEnum] that was successfully decoded
  /// from the passed [data] value on success, null otherwise.
  ///
  /// If [allowNull] is true and the [dynamic value][data] cannot be decoded successfully,
  /// then null is returned. However, if [allowNull] is false and the [dynamic value][data]
  /// cannot be decoded successfully, then an [UnimplementedError] is thrown.
  ///
  /// The [allowNull] is very handy when an API changes and a new enum value is added or removed,
  /// and users are still using an old app with the old code.
  ApprovalRequestStateEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is ApprovalRequestStateEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'pending':
          return ApprovalRequestStateEnum.pending;
        case r'once':
          return ApprovalRequestStateEnum.once;
        case r'always':
          return ApprovalRequestStateEnum.always;
        case r'deny':
          return ApprovalRequestStateEnum.deny;
        case r'timeout':
          return ApprovalRequestStateEnum.timeout;
        case r'cancelled':
          return ApprovalRequestStateEnum.cancelled;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  /// The singleton instance of this transformer.
  static ApprovalRequestStateEnumTypeTransformer? _instance;
}

/// Who decided, from the calling device's point of view.
enum ApprovalRequestDecidedByEnum {
  thisDevice._(r'this_device'),
  otherDevice._(r'other_device'),
  ;

  /// Instantiate a new enum with the provided value.
  const ApprovalRequestDecidedByEnum._(this._value);

  /// The underlying value of this enum member.
  final String _value;

  @override
  String toString() => _value;

  /// Encodes this enum as a value suitable for JSON.
  String toJson() => _value;

  /// Returns the instance of [ApprovalRequestDecidedByEnum] that was successfully decoded
  /// from the passed [value] on success, null otherwise.
  static ApprovalRequestDecidedByEnum? fromJson(dynamic value) =>
      ApprovalRequestDecidedByEnumTypeTransformer().decode(value);

  /// Returns a [List] containing instances of [ApprovalRequestDecidedByEnum]
  /// that were successfully decoded from the passed [JSON][json].
  static List<ApprovalRequestDecidedByEnum> listFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final result = <ApprovalRequestDecidedByEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = ApprovalRequestDecidedByEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

/// Transformation class that can [encode] an instance of [ApprovalRequestDecidedByEnum] to String,
/// and [decode] dynamic data back to [ApprovalRequestDecidedByEnum].
class ApprovalRequestDecidedByEnumTypeTransformer {
  factory ApprovalRequestDecidedByEnumTypeTransformer() =>
      _instance ??= const ApprovalRequestDecidedByEnumTypeTransformer._();

  const ApprovalRequestDecidedByEnumTypeTransformer._();

  String encode(ApprovalRequestDecidedByEnum data) => data._value;

  /// Returns the instance of [ApprovalRequestDecidedByEnum] that was successfully decoded
  /// from the passed [data] value on success, null otherwise.
  ///
  /// If [allowNull] is true and the [dynamic value][data] cannot be decoded successfully,
  /// then null is returned. However, if [allowNull] is false and the [dynamic value][data]
  /// cannot be decoded successfully, then an [UnimplementedError] is thrown.
  ///
  /// The [allowNull] is very handy when an API changes and a new enum value is added or removed,
  /// and users are still using an old app with the old code.
  ApprovalRequestDecidedByEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is ApprovalRequestDecidedByEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'this_device':
          return ApprovalRequestDecidedByEnum.thisDevice;
        case r'other_device':
          return ApprovalRequestDecidedByEnum.otherDevice;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  /// The singleton instance of this transformer.
  static ApprovalRequestDecidedByEnumTypeTransformer? _instance;
}
