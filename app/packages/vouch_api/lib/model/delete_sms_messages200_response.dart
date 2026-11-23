//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of vouch_api;

class DeleteSmsMessages200Response {
  /// Returns a new [DeleteSmsMessages200Response] instance.
  DeleteSmsMessages200Response({
    required this.deleted,
  });

  /// Minimum value: 0
  int deleted;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DeleteSmsMessages200Response && other.deleted == deleted;

  @override
  int get hashCode =>
      // ignore: unnecessary_parenthesis
      (deleted.hashCode);

  @override
  String toString() => 'DeleteSmsMessages200Response[deleted=$deleted]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    json[r'deleted'] = this.deleted;
    return json;
  }

  /// Returns a new [DeleteSmsMessages200Response] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static DeleteSmsMessages200Response? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'deleted'),
            'Required key "DeleteSmsMessages200Response[deleted]" is missing from JSON.');
        assert(json[r'deleted'] != null,
            'Required key "DeleteSmsMessages200Response[deleted]" has a null value in JSON.');
        return true;
      }());

      return DeleteSmsMessages200Response(
        deleted: mapValueOfType<int>(json, r'deleted')!,
      );
    }
    return null;
  }

  static List<DeleteSmsMessages200Response> listFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final result = <DeleteSmsMessages200Response>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = DeleteSmsMessages200Response.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, DeleteSmsMessages200Response> mapFromJson(dynamic json) {
    final map = <String, DeleteSmsMessages200Response>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = DeleteSmsMessages200Response.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of DeleteSmsMessages200Response-objects as value to a dart map
  static Map<String, List<DeleteSmsMessages200Response>> mapListFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final map = <String, List<DeleteSmsMessages200Response>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = DeleteSmsMessages200Response.listFromJson(
          entry.value,
          growable: growable,
        );
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'deleted',
  };
}
