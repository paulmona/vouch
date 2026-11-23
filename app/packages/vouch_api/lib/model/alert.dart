//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of vouch_api;

class Alert {
  /// Returns a new [Alert] instance.
  Alert({
    required this.alertId,
    required this.severity,
    required this.title,
    required this.body,
    required this.createdAt,
  });

  String alertId;

  AlertSeverityEnum severity;

  String title;

  String body;

  /// RFC 3339, UTC.
  DateTime createdAt;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Alert &&
          other.alertId == alertId &&
          other.severity == severity &&
          other.title == title &&
          other.body == body &&
          other.createdAt == createdAt;

  @override
  int get hashCode =>
      // ignore: unnecessary_parenthesis
      (alertId.hashCode) +
      (severity.hashCode) +
      (title.hashCode) +
      (body.hashCode) +
      (createdAt.hashCode);

  @override
  String toString() =>
      'Alert[alertId=$alertId, severity=$severity, title=$title, body=$body, createdAt=$createdAt]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    json[r'alert_id'] = this.alertId;
    json[r'severity'] = this.severity;
    json[r'title'] = this.title;
    json[r'body'] = this.body;
    json[r'created_at'] = this.createdAt.toUtc().toIso8601String();
    return json;
  }

  /// Returns a new [Alert] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static Alert? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'alert_id'),
            'Required key "Alert[alert_id]" is missing from JSON.');
        assert(json[r'alert_id'] != null,
            'Required key "Alert[alert_id]" has a null value in JSON.');
        assert(json.containsKey(r'severity'),
            'Required key "Alert[severity]" is missing from JSON.');
        assert(json[r'severity'] != null,
            'Required key "Alert[severity]" has a null value in JSON.');
        assert(json.containsKey(r'title'),
            'Required key "Alert[title]" is missing from JSON.');
        assert(json[r'title'] != null,
            'Required key "Alert[title]" has a null value in JSON.');
        assert(json.containsKey(r'body'),
            'Required key "Alert[body]" is missing from JSON.');
        assert(json[r'body'] != null,
            'Required key "Alert[body]" has a null value in JSON.');
        assert(json.containsKey(r'created_at'),
            'Required key "Alert[created_at]" is missing from JSON.');
        assert(json[r'created_at'] != null,
            'Required key "Alert[created_at]" has a null value in JSON.');
        return true;
      }());

      return Alert(
        alertId: mapValueOfType<String>(json, r'alert_id')!,
        severity: AlertSeverityEnum.fromJson(json[r'severity'])!,
        title: mapValueOfType<String>(json, r'title')!,
        body: mapValueOfType<String>(json, r'body')!,
        createdAt: mapDateTime(json, r'created_at', r'')!,
      );
    }
    return null;
  }

  static List<Alert> listFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final result = <Alert>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = Alert.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, Alert> mapFromJson(dynamic json) {
    final map = <String, Alert>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = Alert.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of Alert-objects as value to a dart map
  static Map<String, List<Alert>> mapListFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final map = <String, List<Alert>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = Alert.listFromJson(
          entry.value,
          growable: growable,
        );
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'alert_id',
    'severity',
    'title',
    'body',
    'created_at',
  };
}

enum AlertSeverityEnum {
  info._(r'info'),
  warning._(r'warning'),
  critical._(r'critical'),
  ;

  /// Instantiate a new enum with the provided value.
  const AlertSeverityEnum._(this._value);

  /// The underlying value of this enum member.
  final String _value;

  @override
  String toString() => _value;

  /// Encodes this enum as a value suitable for JSON.
  String toJson() => _value;

  /// Returns the instance of [AlertSeverityEnum] that was successfully decoded
  /// from the passed [value] on success, null otherwise.
  static AlertSeverityEnum? fromJson(dynamic value) =>
      AlertSeverityEnumTypeTransformer().decode(value);

  /// Returns a [List] containing instances of [AlertSeverityEnum]
  /// that were successfully decoded from the passed [JSON][json].
  static List<AlertSeverityEnum> listFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final result = <AlertSeverityEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = AlertSeverityEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

/// Transformation class that can [encode] an instance of [AlertSeverityEnum] to String,
/// and [decode] dynamic data back to [AlertSeverityEnum].
class AlertSeverityEnumTypeTransformer {
  factory AlertSeverityEnumTypeTransformer() =>
      _instance ??= const AlertSeverityEnumTypeTransformer._();

  const AlertSeverityEnumTypeTransformer._();

  String encode(AlertSeverityEnum data) => data._value;

  /// Returns the instance of [AlertSeverityEnum] that was successfully decoded
  /// from the passed [data] value on success, null otherwise.
  ///
  /// If [allowNull] is true and the [dynamic value][data] cannot be decoded successfully,
  /// then null is returned. However, if [allowNull] is false and the [dynamic value][data]
  /// cannot be decoded successfully, then an [UnimplementedError] is thrown.
  ///
  /// The [allowNull] is very handy when an API changes and a new enum value is added or removed,
  /// and users are still using an old app with the old code.
  AlertSeverityEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is AlertSeverityEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'info':
          return AlertSeverityEnum.info;
        case r'warning':
          return AlertSeverityEnum.warning;
        case r'critical':
          return AlertSeverityEnum.critical;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  /// The singleton instance of this transformer.
  static AlertSeverityEnumTypeTransformer? _instance;
}
