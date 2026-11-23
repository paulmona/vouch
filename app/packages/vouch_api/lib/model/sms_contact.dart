//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of vouch_api;

class SmsContact {
  /// Returns a new [SmsContact] instance.
  SmsContact({
    required this.phone,
    required this.name,
    required this.addedAt,
    required this.addedBy,
  });

  /// E.164.
  String phone;

  String name;

  /// RFC 3339, UTC.
  DateTime addedAt;

  /// `owner`: picked in the app. `agent_request`: an approved `sms_contact` request. `import`: carried over from before Vouch owned SMS.
  SmsContactAddedByEnum addedBy;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SmsContact &&
          other.phone == phone &&
          other.name == name &&
          other.addedAt == addedAt &&
          other.addedBy == addedBy;

  @override
  int get hashCode =>
      // ignore: unnecessary_parenthesis
      (phone.hashCode) +
      (name.hashCode) +
      (addedAt.hashCode) +
      (addedBy.hashCode);

  @override
  String toString() =>
      'SmsContact[phone=$phone, name=$name, addedAt=$addedAt, addedBy=$addedBy]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    json[r'phone'] = this.phone;
    json[r'name'] = this.name;
    json[r'added_at'] = this.addedAt.toUtc().toIso8601String();
    json[r'added_by'] = this.addedBy;
    return json;
  }

  /// Returns a new [SmsContact] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static SmsContact? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'phone'),
            'Required key "SmsContact[phone]" is missing from JSON.');
        assert(json[r'phone'] != null,
            'Required key "SmsContact[phone]" has a null value in JSON.');
        assert(json.containsKey(r'name'),
            'Required key "SmsContact[name]" is missing from JSON.');
        assert(json[r'name'] != null,
            'Required key "SmsContact[name]" has a null value in JSON.');
        assert(json.containsKey(r'added_at'),
            'Required key "SmsContact[added_at]" is missing from JSON.');
        assert(json[r'added_at'] != null,
            'Required key "SmsContact[added_at]" has a null value in JSON.');
        assert(json.containsKey(r'added_by'),
            'Required key "SmsContact[added_by]" is missing from JSON.');
        assert(json[r'added_by'] != null,
            'Required key "SmsContact[added_by]" has a null value in JSON.');
        return true;
      }());

      return SmsContact(
        phone: mapValueOfType<String>(json, r'phone')!,
        name: mapValueOfType<String>(json, r'name')!,
        addedAt: mapDateTime(json, r'added_at', r'')!,
        addedBy: SmsContactAddedByEnum.fromJson(json[r'added_by'])!,
      );
    }
    return null;
  }

  static List<SmsContact> listFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final result = <SmsContact>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = SmsContact.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, SmsContact> mapFromJson(dynamic json) {
    final map = <String, SmsContact>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = SmsContact.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of SmsContact-objects as value to a dart map
  static Map<String, List<SmsContact>> mapListFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final map = <String, List<SmsContact>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = SmsContact.listFromJson(
          entry.value,
          growable: growable,
        );
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'phone',
    'name',
    'added_at',
    'added_by',
  };
}

/// `owner`: picked in the app. `agent_request`: an approved `sms_contact` request. `import`: carried over from before Vouch owned SMS.
enum SmsContactAddedByEnum {
  owner._(r'owner'),
  agentRequest._(r'agent_request'),
  import_._(r'import'),
  ;

  /// Instantiate a new enum with the provided value.
  const SmsContactAddedByEnum._(this._value);

  /// The underlying value of this enum member.
  final String _value;

  @override
  String toString() => _value;

  /// Encodes this enum as a value suitable for JSON.
  String toJson() => _value;

  /// Returns the instance of [SmsContactAddedByEnum] that was successfully decoded
  /// from the passed [value] on success, null otherwise.
  static SmsContactAddedByEnum? fromJson(dynamic value) =>
      SmsContactAddedByEnumTypeTransformer().decode(value);

  /// Returns a [List] containing instances of [SmsContactAddedByEnum]
  /// that were successfully decoded from the passed [JSON][json].
  static List<SmsContactAddedByEnum> listFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final result = <SmsContactAddedByEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = SmsContactAddedByEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

/// Transformation class that can [encode] an instance of [SmsContactAddedByEnum] to String,
/// and [decode] dynamic data back to [SmsContactAddedByEnum].
class SmsContactAddedByEnumTypeTransformer {
  factory SmsContactAddedByEnumTypeTransformer() =>
      _instance ??= const SmsContactAddedByEnumTypeTransformer._();

  const SmsContactAddedByEnumTypeTransformer._();

  String encode(SmsContactAddedByEnum data) => data._value;

  /// Returns the instance of [SmsContactAddedByEnum] that was successfully decoded
  /// from the passed [data] value on success, null otherwise.
  ///
  /// If [allowNull] is true and the [dynamic value][data] cannot be decoded successfully,
  /// then null is returned. However, if [allowNull] is false and the [dynamic value][data]
  /// cannot be decoded successfully, then an [UnimplementedError] is thrown.
  ///
  /// The [allowNull] is very handy when an API changes and a new enum value is added or removed,
  /// and users are still using an old app with the old code.
  SmsContactAddedByEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is SmsContactAddedByEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'owner':
          return SmsContactAddedByEnum.owner;
        case r'agent_request':
          return SmsContactAddedByEnum.agentRequest;
        case r'import':
          return SmsContactAddedByEnum.import_;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  /// The singleton instance of this transformer.
  static SmsContactAddedByEnumTypeTransformer? _instance;
}
