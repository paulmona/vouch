import 'package:flutter/services.dart';

/// Dart side of `AppSettingsChannel.kt`.
class AppSettings {
  AppSettings({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName);

  static const channelName = 'ai.viewbridge.vouch/app_settings';
  final MethodChannel _channel;

  /// e.g. "Google Pixel 9" or "iPhone"; the default pairing name.
  Future<String> deviceName() async =>
      await _channel.invokeMethod<String>('deviceName') ?? 'Phone';

  /// "fingerprint", "Face ID" or "Touch ID": what this phone calls it.
  Future<String> biometryName() async =>
      await _channel.invokeMethod<String>('biometryName') ?? 'fingerprint';

  /// Android only; iOS has no such list and answers true.
  Future<bool> isIgnoringBatteryOptimizations() async =>
      await _channel.invokeMethod<bool>('isIgnoringBatteryOptimizations') ??
      false;

  /// Opens the system "let this app run in the background" dialog.
  Future<void> requestIgnoreBatteryOptimizations() =>
      _channel.invokeMethod<void>('requestIgnoreBatteryOptimizations');

  Future<void> openBatterySettings() =>
      _channel.invokeMethod<void>('openBatterySettings');
}
