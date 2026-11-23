//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of vouch_api;

class ListSmsMessages200Response {
  /// Returns a new [ListSmsMessages200Response] instance.
  ListSmsMessages200Response({
    this.messages = const [],
    required this.nextBefore,
  });

  List<SmsMessage> messages;

  /// Pass as `before` for the next older page; null when there are no older messages.
  String? nextBefore;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ListSmsMessages200Response &&
          _deepEquality.equals(other.messages, messages) &&
          other.nextBefore == nextBefore;

  @override
  int get hashCode =>
      // ignore: unnecessary_parenthesis
      (messages.hashCode) + (nextBefore == null ? 0 : nextBefore!.hashCode);

  @override
  String toString() =>
      'ListSmsMessages200Response[messages=$messages, nextBefore=$nextBefore]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    json[r'messages'] = this.messages;
    if (this.nextBefore != null) {
      json[r'next_before'] = this.nextBefore;
    } else {
      json[r'next_before'] = null;
    }
    return json;
  }

  /// Returns a new [ListSmsMessages200Response] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static ListSmsMessages200Response? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'messages'),
            'Required key "ListSmsMessages200Response[messages]" is missing from JSON.');
        assert(json[r'messages'] != null,
            'Required key "ListSmsMessages200Response[messages]" has a null value in JSON.');
        assert(json.containsKey(r'next_before'),
            'Required key "ListSmsMessages200Response[next_before]" is missing from JSON.');
        return true;
      }());

      return ListSmsMessages200Response(
        messages: SmsMessage.listFromJson(json[r'messages']),
        nextBefore: mapValueOfType<String>(json, r'next_before'),
      );
    }
    return null;
  }

  static List<ListSmsMessages200Response> listFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final result = <ListSmsMessages200Response>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = ListSmsMessages200Response.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, ListSmsMessages200Response> mapFromJson(dynamic json) {
    final map = <String, ListSmsMessages200Response>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = ListSmsMessages200Response.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of ListSmsMessages200Response-objects as value to a dart map
  static Map<String, List<ListSmsMessages200Response>> mapListFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final map = <String, List<ListSmsMessages200Response>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = ListSmsMessages200Response.listFromJson(
          entry.value,
          growable: growable,
        );
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'messages',
    'next_before',
  };
}
