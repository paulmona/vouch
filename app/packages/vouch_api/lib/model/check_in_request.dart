//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of vouch_api;

class CheckInRequest {
  /// Returns a new [CheckInRequest] instance.
  CheckInRequest({
    this.heartbeatId,
  });

  /// The ID from the heartbeat push, or null for an app-open check-in.
  String? heartbeatId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CheckInRequest && other.heartbeatId == heartbeatId;

  @override
  int get hashCode =>
      // ignore: unnecessary_parenthesis
      (heartbeatId == null ? 0 : heartbeatId!.hashCode);

  @override
  String toString() => 'CheckInRequest[heartbeatId=$heartbeatId]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    if (this.heartbeatId != null) {
      json[r'heartbeat_id'] = this.heartbeatId;
    } else {
      json[r'heartbeat_id'] = null;
    }
    return json;
  }

  /// Returns a new [CheckInRequest] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static CheckInRequest? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        return true;
      }());

      return CheckInRequest(
        heartbeatId: mapValueOfType<String>(json, r'heartbeat_id'),
      );
    }
    return null;
  }

  static List<CheckInRequest> listFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final result = <CheckInRequest>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = CheckInRequest.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, CheckInRequest> mapFromJson(dynamic json) {
    final map = <String, CheckInRequest>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = CheckInRequest.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of CheckInRequest-objects as value to a dart map
  static Map<String, List<CheckInRequest>> mapListFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final map = <String, List<CheckInRequest>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = CheckInRequest.listFromJson(
          entry.value,
          growable: growable,
        );
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{};
}
