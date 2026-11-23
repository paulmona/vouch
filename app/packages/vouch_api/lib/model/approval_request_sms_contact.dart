//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of vouch_api;

class ApprovalRequestSmsContact {
  /// Returns a new [ApprovalRequestSmsContact] instance.
  ApprovalRequestSmsContact({
    required this.phone,
    required this.name,
    required this.reason,
  });

  /// E.164.
  String phone;

  String name;

  /// The agent's stated reason, shown as written.
  String reason;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ApprovalRequestSmsContact &&
          other.phone == phone &&
          other.name == name &&
          other.reason == reason;

  @override
  int get hashCode =>
      // ignore: unnecessary_parenthesis
      (phone.hashCode) + (name.hashCode) + (reason.hashCode);

  @override
  String toString() =>
      'ApprovalRequestSmsContact[phone=$phone, name=$name, reason=$reason]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    json[r'phone'] = this.phone;
    json[r'name'] = this.name;
    json[r'reason'] = this.reason;
    return json;
  }

  /// Returns a new [ApprovalRequestSmsContact] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static ApprovalRequestSmsContact? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'phone'),
            'Required key "ApprovalRequestSmsContact[phone]" is missing from JSON.');
        assert(json[r'phone'] != null,
            'Required key "ApprovalRequestSmsContact[phone]" has a null value in JSON.');
        assert(json.containsKey(r'name'),
            'Required key "ApprovalRequestSmsContact[name]" is missing from JSON.');
        assert(json[r'name'] != null,
            'Required key "ApprovalRequestSmsContact[name]" has a null value in JSON.');
        assert(json.containsKey(r'reason'),
            'Required key "ApprovalRequestSmsContact[reason]" is missing from JSON.');
        assert(json[r'reason'] != null,
            'Required key "ApprovalRequestSmsContact[reason]" has a null value in JSON.');
        return true;
      }());

      return ApprovalRequestSmsContact(
        phone: mapValueOfType<String>(json, r'phone')!,
        name: mapValueOfType<String>(json, r'name')!,
        reason: mapValueOfType<String>(json, r'reason')!,
      );
    }
    return null;
  }

  static List<ApprovalRequestSmsContact> listFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final result = <ApprovalRequestSmsContact>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = ApprovalRequestSmsContact.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, ApprovalRequestSmsContact> mapFromJson(dynamic json) {
    final map = <String, ApprovalRequestSmsContact>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = ApprovalRequestSmsContact.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of ApprovalRequestSmsContact-objects as value to a dart map
  static Map<String, List<ApprovalRequestSmsContact>> mapListFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final map = <String, List<ApprovalRequestSmsContact>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = ApprovalRequestSmsContact.listFromJson(
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
    'reason',
  };
}
