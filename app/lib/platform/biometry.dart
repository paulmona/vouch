import 'dart:io' show Platform;

/// The words for the biometric on this phone, so the same screens read
/// naturally on both: "fingerprint" on Android, "Face ID" or "Touch ID" on
/// iPhone. [init] asks the platform once at startup; before that, and in
/// tests, the Android wording applies.
abstract final class Biometry {
  static String _name = 'fingerprint';

  static Future<void> init(Future<String> Function() lookup) async {
    try {
      final n = await lookup();
      if (n.isNotEmpty) _name = n;
    } on Object {
      // Keep the default; wording only.
    }
  }

  /// "fingerprint", "Face ID" or "Touch ID".
  static String get name => _name;

  static bool get _isAppleName => _name != 'fingerprint';

  /// "your fingerprint" / "Face ID": the object in "needs ...".
  static String get yours => _isAppleName ? _name : 'your $_name';

  /// "Confirming with your fingerprint" / "Confirming with Face ID".
  static String get withYours => 'with $yours';

  /// "Add a fingerprint in your phone settings" / "Set up Face ID in
  /// Settings".
  static String get setupHint => _isAppleName
      ? 'Set up $_name in Settings'
      : 'Add a $_name in your phone settings';

  /// "fingerprint-bound" / "Face ID-bound".
  static String get bound => '$_name-bound';

  /// "Fingerprint" / "Face ID" as a title word.
  static String get title =>
      _isAppleName ? _name : '${_name[0].toUpperCase()}${_name.substring(1)}';

  /// The sentence for a key killed by an enrolment change.
  static String get changedNotice => _isAppleName
      ? '$_name changed on this phone, so its key was reset.'
      : 'The ${_name}s on this phone changed, so its key was reset.';

  /// True on iPhone/iPad; the few screens with Android-only rows use it.
  static bool get isApple => Platform.isIOS;
}
