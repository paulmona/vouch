//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of vouch_api;

enum Platform {
  android._(r'android'),
  ios._(r'ios'),
  ;

  /// Instantiate a new enum with the provided value.
  const Platform._(this._value);

  /// The underlying value of this enum member.
  final String _value;

  @override
  String toString() => _value;

  /// Encodes this enum as a value suitable for JSON.
  String toJson() => _value;

  /// Returns the instance of [Platform] that was successfully decoded
  /// from the passed [value] on success, null otherwise.
  static Platform? fromJson(dynamic value) =>
      PlatformTypeTransformer().decode(value);

  /// Returns a [List] containing instances of [Platform]
  /// that were successfully decoded from the passed [JSON][json].
  static List<Platform> listFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final result = <Platform>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = Platform.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

/// Transformation class that can [encode] an instance of [Platform] to String,
/// and [decode] dynamic data back to [Platform].
class PlatformTypeTransformer {
  factory PlatformTypeTransformer() =>
      _instance ??= const PlatformTypeTransformer._();

  const PlatformTypeTransformer._();

  /// Encodes this enum as a value suitable for JSON.
  String encode(Platform data) => data._value;

  /// Returns the instance of [Platform] that was successfully decoded
  /// from the passed [data] value on success, null otherwise.
  ///
  /// If [allowNull] is true and the [dynamic value][data] cannot be decoded successfully,
  /// then null is returned. However, if [allowNull] is false and the [dynamic value][data]
  /// cannot be decoded successfully, then an [UnimplementedError] is thrown.
  ///
  /// The [allowNull] is very handy when an API changes and a new enum value is added or removed,
  /// and users are still using an old app with the old code.
  Platform? decode(dynamic data, {bool allowNull = true}) {
    if (data is Platform) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'android':
          return Platform.android;
        case r'ios':
          return Platform.ios;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  /// The singleton instance of this transformer.
  static PlatformTypeTransformer? _instance;
}
