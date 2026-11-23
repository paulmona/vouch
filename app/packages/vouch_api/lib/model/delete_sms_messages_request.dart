//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of vouch_api;

class DeleteSmsMessagesRequest {
  /// Returns a new [DeleteSmsMessagesRequest] instance.
  DeleteSmsMessagesRequest({
    this.messageIds = const {},
  });

  Set<String> messageIds;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DeleteSmsMessagesRequest &&
          _deepEquality.equals(other.messageIds, messageIds);

  @override
  int get hashCode =>
      // ignore: unnecessary_parenthesis
      (messageIds.hashCode);

  @override
  String toString() => 'DeleteSmsMessagesRequest[messageIds=$messageIds]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    json[r'message_ids'] = this.messageIds.toList(growable: false);
    return json;
  }

  /// Returns a new [DeleteSmsMessagesRequest] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static DeleteSmsMessagesRequest? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'message_ids'),
            'Required key "DeleteSmsMessagesRequest[message_ids]" is missing from JSON.');
        assert(json[r'message_ids'] != null,
            'Required key "DeleteSmsMessagesRequest[message_ids]" has a null value in JSON.');
        return true;
      }());

      return DeleteSmsMessagesRequest(
        messageIds: json[r'message_ids'] is Iterable
            ? (json[r'message_ids'] as Iterable).cast<String>().toSet()
            : const {},
      );
    }
    return null;
  }

  static List<DeleteSmsMessagesRequest> listFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final result = <DeleteSmsMessagesRequest>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = DeleteSmsMessagesRequest.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, DeleteSmsMessagesRequest> mapFromJson(dynamic json) {
    final map = <String, DeleteSmsMessagesRequest>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = DeleteSmsMessagesRequest.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of DeleteSmsMessagesRequest-objects as value to a dart map
  static Map<String, List<DeleteSmsMessagesRequest>> mapListFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final map = <String, List<DeleteSmsMessagesRequest>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = DeleteSmsMessagesRequest.listFromJson(
          entry.value,
          growable: growable,
        );
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'message_ids',
  };
}
