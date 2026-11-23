//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of vouch_api;

class SmsMessage {
  /// Returns a new [SmsMessage] instance.
  SmsMessage({
    required this.messageId,
    required this.phone,
    required this.direction,
    required this.text,
    required this.at,
    required this.status,
  });

  String messageId;

  /// E.164.
  String phone;

  SmsMessageDirectionEnum direction;

  String text;

  /// When it was received, or sent by the agent.
  DateTime at;

  /// `received` for inbound. Outbound is `sent` once the provider accepted it, `failed` if it refused.
  SmsMessageStatusEnum status;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SmsMessage &&
          other.messageId == messageId &&
          other.phone == phone &&
          other.direction == direction &&
          other.text == text &&
          other.at == at &&
          other.status == status;

  @override
  int get hashCode =>
      // ignore: unnecessary_parenthesis
      (messageId.hashCode) +
      (phone.hashCode) +
      (direction.hashCode) +
      (text.hashCode) +
      (at.hashCode) +
      (status.hashCode);

  @override
  String toString() =>
      'SmsMessage[messageId=$messageId, phone=$phone, direction=$direction, text=$text, at=$at, status=$status]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    json[r'message_id'] = this.messageId;
    json[r'phone'] = this.phone;
    json[r'direction'] = this.direction;
    json[r'text'] = this.text;
    json[r'at'] = this.at.toUtc().toIso8601String();
    json[r'status'] = this.status;
    return json;
  }

  /// Returns a new [SmsMessage] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static SmsMessage? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'message_id'),
            'Required key "SmsMessage[message_id]" is missing from JSON.');
        assert(json[r'message_id'] != null,
            'Required key "SmsMessage[message_id]" has a null value in JSON.');
        assert(json.containsKey(r'phone'),
            'Required key "SmsMessage[phone]" is missing from JSON.');
        assert(json[r'phone'] != null,
            'Required key "SmsMessage[phone]" has a null value in JSON.');
        assert(json.containsKey(r'direction'),
            'Required key "SmsMessage[direction]" is missing from JSON.');
        assert(json[r'direction'] != null,
            'Required key "SmsMessage[direction]" has a null value in JSON.');
        assert(json.containsKey(r'text'),
            'Required key "SmsMessage[text]" is missing from JSON.');
        assert(json[r'text'] != null,
            'Required key "SmsMessage[text]" has a null value in JSON.');
        assert(json.containsKey(r'at'),
            'Required key "SmsMessage[at]" is missing from JSON.');
        assert(json[r'at'] != null,
            'Required key "SmsMessage[at]" has a null value in JSON.');
        assert(json.containsKey(r'status'),
            'Required key "SmsMessage[status]" is missing from JSON.');
        assert(json[r'status'] != null,
            'Required key "SmsMessage[status]" has a null value in JSON.');
        return true;
      }());

      return SmsMessage(
        messageId: mapValueOfType<String>(json, r'message_id')!,
        phone: mapValueOfType<String>(json, r'phone')!,
        direction: SmsMessageDirectionEnum.fromJson(json[r'direction'])!,
        text: mapValueOfType<String>(json, r'text')!,
        at: mapDateTime(json, r'at', r'')!,
        status: SmsMessageStatusEnum.fromJson(json[r'status'])!,
      );
    }
    return null;
  }

  static List<SmsMessage> listFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final result = <SmsMessage>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = SmsMessage.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, SmsMessage> mapFromJson(dynamic json) {
    final map = <String, SmsMessage>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = SmsMessage.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of SmsMessage-objects as value to a dart map
  static Map<String, List<SmsMessage>> mapListFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final map = <String, List<SmsMessage>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = SmsMessage.listFromJson(
          entry.value,
          growable: growable,
        );
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'message_id',
    'phone',
    'direction',
    'text',
    'at',
    'status',
  };
}

enum SmsMessageDirectionEnum {
  inbound._(r'inbound'),
  outbound._(r'outbound'),
  ;

  /// Instantiate a new enum with the provided value.
  const SmsMessageDirectionEnum._(this._value);

  /// The underlying value of this enum member.
  final String _value;

  @override
  String toString() => _value;

  /// Encodes this enum as a value suitable for JSON.
  String toJson() => _value;

  /// Returns the instance of [SmsMessageDirectionEnum] that was successfully decoded
  /// from the passed [value] on success, null otherwise.
  static SmsMessageDirectionEnum? fromJson(dynamic value) =>
      SmsMessageDirectionEnumTypeTransformer().decode(value);

  /// Returns a [List] containing instances of [SmsMessageDirectionEnum]
  /// that were successfully decoded from the passed [JSON][json].
  static List<SmsMessageDirectionEnum> listFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final result = <SmsMessageDirectionEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = SmsMessageDirectionEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

/// Transformation class that can [encode] an instance of [SmsMessageDirectionEnum] to String,
/// and [decode] dynamic data back to [SmsMessageDirectionEnum].
class SmsMessageDirectionEnumTypeTransformer {
  factory SmsMessageDirectionEnumTypeTransformer() =>
      _instance ??= const SmsMessageDirectionEnumTypeTransformer._();

  const SmsMessageDirectionEnumTypeTransformer._();

  String encode(SmsMessageDirectionEnum data) => data._value;

  /// Returns the instance of [SmsMessageDirectionEnum] that was successfully decoded
  /// from the passed [data] value on success, null otherwise.
  ///
  /// If [allowNull] is true and the [dynamic value][data] cannot be decoded successfully,
  /// then null is returned. However, if [allowNull] is false and the [dynamic value][data]
  /// cannot be decoded successfully, then an [UnimplementedError] is thrown.
  ///
  /// The [allowNull] is very handy when an API changes and a new enum value is added or removed,
  /// and users are still using an old app with the old code.
  SmsMessageDirectionEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is SmsMessageDirectionEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'inbound':
          return SmsMessageDirectionEnum.inbound;
        case r'outbound':
          return SmsMessageDirectionEnum.outbound;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  /// The singleton instance of this transformer.
  static SmsMessageDirectionEnumTypeTransformer? _instance;
}

/// `received` for inbound. Outbound is `sent` once the provider accepted it, `failed` if it refused.
enum SmsMessageStatusEnum {
  received._(r'received'),
  sent._(r'sent'),
  failed._(r'failed'),
  ;

  /// Instantiate a new enum with the provided value.
  const SmsMessageStatusEnum._(this._value);

  /// The underlying value of this enum member.
  final String _value;

  @override
  String toString() => _value;

  /// Encodes this enum as a value suitable for JSON.
  String toJson() => _value;

  /// Returns the instance of [SmsMessageStatusEnum] that was successfully decoded
  /// from the passed [value] on success, null otherwise.
  static SmsMessageStatusEnum? fromJson(dynamic value) =>
      SmsMessageStatusEnumTypeTransformer().decode(value);

  /// Returns a [List] containing instances of [SmsMessageStatusEnum]
  /// that were successfully decoded from the passed [JSON][json].
  static List<SmsMessageStatusEnum> listFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final result = <SmsMessageStatusEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = SmsMessageStatusEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

/// Transformation class that can [encode] an instance of [SmsMessageStatusEnum] to String,
/// and [decode] dynamic data back to [SmsMessageStatusEnum].
class SmsMessageStatusEnumTypeTransformer {
  factory SmsMessageStatusEnumTypeTransformer() =>
      _instance ??= const SmsMessageStatusEnumTypeTransformer._();

  const SmsMessageStatusEnumTypeTransformer._();

  String encode(SmsMessageStatusEnum data) => data._value;

  /// Returns the instance of [SmsMessageStatusEnum] that was successfully decoded
  /// from the passed [data] value on success, null otherwise.
  ///
  /// If [allowNull] is true and the [dynamic value][data] cannot be decoded successfully,
  /// then null is returned. However, if [allowNull] is false and the [dynamic value][data]
  /// cannot be decoded successfully, then an [UnimplementedError] is thrown.
  ///
  /// The [allowNull] is very handy when an API changes and a new enum value is added or removed,
  /// and users are still using an old app with the old code.
  SmsMessageStatusEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is SmsMessageStatusEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'received':
          return SmsMessageStatusEnum.received;
        case r'sent':
          return SmsMessageStatusEnum.sent;
        case r'failed':
          return SmsMessageStatusEnum.failed;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  /// The singleton instance of this transformer.
  static SmsMessageStatusEnumTypeTransformer? _instance;
}
