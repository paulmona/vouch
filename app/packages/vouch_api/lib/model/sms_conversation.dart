//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of vouch_api;

class SmsConversation {
  /// Returns a new [SmsConversation] instance.
  SmsConversation({
    required this.phone,
    required this.contactName,
    required this.lastMessage,
    required this.unreadCount,
  });

  /// E.164.
  String phone;

  /// The permitted contact's name, or null for a number that is not (or no longer) permitted.
  String? contactName;

  SmsMessage lastMessage;

  /// Minimum value: 0
  int unreadCount;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SmsConversation &&
          other.phone == phone &&
          other.contactName == contactName &&
          other.lastMessage == lastMessage &&
          other.unreadCount == unreadCount;

  @override
  int get hashCode =>
      // ignore: unnecessary_parenthesis
      (phone.hashCode) +
      (contactName == null ? 0 : contactName!.hashCode) +
      (lastMessage.hashCode) +
      (unreadCount.hashCode);

  @override
  String toString() =>
      'SmsConversation[phone=$phone, contactName=$contactName, lastMessage=$lastMessage, unreadCount=$unreadCount]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    json[r'phone'] = this.phone;
    if (this.contactName != null) {
      json[r'contact_name'] = this.contactName;
    } else {
      json[r'contact_name'] = null;
    }
    json[r'last_message'] = this.lastMessage;
    json[r'unread_count'] = this.unreadCount;
    return json;
  }

  /// Returns a new [SmsConversation] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static SmsConversation? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'phone'),
            'Required key "SmsConversation[phone]" is missing from JSON.');
        assert(json[r'phone'] != null,
            'Required key "SmsConversation[phone]" has a null value in JSON.');
        assert(json.containsKey(r'contact_name'),
            'Required key "SmsConversation[contact_name]" is missing from JSON.');
        assert(json.containsKey(r'last_message'),
            'Required key "SmsConversation[last_message]" is missing from JSON.');
        assert(json[r'last_message'] != null,
            'Required key "SmsConversation[last_message]" has a null value in JSON.');
        assert(json.containsKey(r'unread_count'),
            'Required key "SmsConversation[unread_count]" is missing from JSON.');
        assert(json[r'unread_count'] != null,
            'Required key "SmsConversation[unread_count]" has a null value in JSON.');
        return true;
      }());

      return SmsConversation(
        phone: mapValueOfType<String>(json, r'phone')!,
        contactName: mapValueOfType<String>(json, r'contact_name'),
        lastMessage: SmsMessage.fromJson(json[r'last_message'])!,
        unreadCount: mapValueOfType<int>(json, r'unread_count')!,
      );
    }
    return null;
  }

  static List<SmsConversation> listFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final result = <SmsConversation>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = SmsConversation.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, SmsConversation> mapFromJson(dynamic json) {
    final map = <String, SmsConversation>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = SmsConversation.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of SmsConversation-objects as value to a dart map
  static Map<String, List<SmsConversation>> mapListFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final map = <String, List<SmsConversation>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = SmsConversation.listFromJson(
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
    'contact_name',
    'last_message',
    'unread_count',
  };
}
