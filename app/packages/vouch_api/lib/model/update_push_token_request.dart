//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of vouch_api;

class UpdatePushTokenRequest {
  /// Returns a new [UpdatePushTokenRequest] instance.
  UpdatePushTokenRequest({
    required this.pushToken,
  });

  String pushToken;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UpdatePushTokenRequest && other.pushToken == pushToken;

  @override
  int get hashCode =>
      // ignore: unnecessary_parenthesis
      (pushToken.hashCode);

  @override
  String toString() => 'UpdatePushTokenRequest[pushToken=$pushToken]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    json[r'push_token'] = this.pushToken;
    return json;
  }

  /// Returns a new [UpdatePushTokenRequest] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static UpdatePushTokenRequest? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'push_token'),
            'Required key "UpdatePushTokenRequest[push_token]" is missing from JSON.');
        assert(json[r'push_token'] != null,
            'Required key "UpdatePushTokenRequest[push_token]" has a null value in JSON.');
        return true;
      }());

      return UpdatePushTokenRequest(
        pushToken: mapValueOfType<String>(json, r'push_token')!,
      );
    }
    return null;
  }

  static List<UpdatePushTokenRequest> listFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final result = <UpdatePushTokenRequest>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = UpdatePushTokenRequest.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, UpdatePushTokenRequest> mapFromJson(dynamic json) {
    final map = <String, UpdatePushTokenRequest>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = UpdatePushTokenRequest.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of UpdatePushTokenRequest-objects as value to a dart map
  static Map<String, List<UpdatePushTokenRequest>> mapListFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final map = <String, List<UpdatePushTokenRequest>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = UpdatePushTokenRequest.listFromJson(
          entry.value,
          growable: growable,
        );
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'push_token',
  };
}
