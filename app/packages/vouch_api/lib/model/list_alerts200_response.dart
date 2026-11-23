//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of vouch_api;

class ListAlerts200Response {
  /// Returns a new [ListAlerts200Response] instance.
  ListAlerts200Response({
    this.alerts = const [],
  });

  List<Alert> alerts;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ListAlerts200Response &&
          _deepEquality.equals(other.alerts, alerts);

  @override
  int get hashCode =>
      // ignore: unnecessary_parenthesis
      (alerts.hashCode);

  @override
  String toString() => 'ListAlerts200Response[alerts=$alerts]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    json[r'alerts'] = this.alerts;
    return json;
  }

  /// Returns a new [ListAlerts200Response] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static ListAlerts200Response? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'alerts'),
            'Required key "ListAlerts200Response[alerts]" is missing from JSON.');
        assert(json[r'alerts'] != null,
            'Required key "ListAlerts200Response[alerts]" has a null value in JSON.');
        return true;
      }());

      return ListAlerts200Response(
        alerts: Alert.listFromJson(json[r'alerts']),
      );
    }
    return null;
  }

  static List<ListAlerts200Response> listFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final result = <ListAlerts200Response>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = ListAlerts200Response.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, ListAlerts200Response> mapFromJson(dynamic json) {
    final map = <String, ListAlerts200Response>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = ListAlerts200Response.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of ListAlerts200Response-objects as value to a dart map
  static Map<String, List<ListAlerts200Response>> mapListFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final map = <String, List<ListAlerts200Response>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = ListAlerts200Response.listFromJson(
          entry.value,
          growable: growable,
        );
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'alerts',
  };
}
