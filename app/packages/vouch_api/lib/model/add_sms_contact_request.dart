//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of vouch_api;

class AddSmsContactRequest {
  /// Returns a new [AddSmsContactRequest] instance.
  AddSmsContactRequest({
    required this.phone,
    required this.name,
  });

  String phone;

  String name;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AddSmsContactRequest &&
          other.phone == phone &&
          other.name == name;

  @override
  int get hashCode =>
      // ignore: unnecessary_parenthesis
      (phone.hashCode) + (name.hashCode);

  @override
  String toString() => 'AddSmsContactRequest[phone=$phone, name=$name]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    json[r'phone'] = this.phone;
    json[r'name'] = this.name;
    return json;
  }

  /// Returns a new [AddSmsContactRequest] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static AddSmsContactRequest? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'phone'),
            'Required key "AddSmsContactRequest[phone]" is missing from JSON.');
        assert(json[r'phone'] != null,
            'Required key "AddSmsContactRequest[phone]" has a null value in JSON.');
        assert(json.containsKey(r'name'),
            'Required key "AddSmsContactRequest[name]" is missing from JSON.');
        assert(json[r'name'] != null,
            'Required key "AddSmsContactRequest[name]" has a null value in JSON.');
        return true;
      }());

      return AddSmsContactRequest(
        phone: mapValueOfType<String>(json, r'phone')!,
        name: mapValueOfType<String>(json, r'name')!,
      );
    }
    return null;
  }

  static List<AddSmsContactRequest> listFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final result = <AddSmsContactRequest>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = AddSmsContactRequest.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, AddSmsContactRequest> mapFromJson(dynamic json) {
    final map = <String, AddSmsContactRequest>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = AddSmsContactRequest.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of AddSmsContactRequest-objects as value to a dart map
  static Map<String, List<AddSmsContactRequest>> mapListFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final map = <String, List<AddSmsContactRequest>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = AddSmsContactRequest.listFromJson(
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
  };
}
