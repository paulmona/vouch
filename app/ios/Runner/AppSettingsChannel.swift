import Flutter
import LocalAuthentication
import UIKit

/// iOS twin of `AppSettingsChannel.kt`. iOS has no battery-optimisation
/// allow-list: the two battery calls report "nothing to do" and open the
/// app's Settings page, so the Dart side needs no platform branches to
/// stay safe (it hides the battery card on iOS anyway).
final class AppSettingsChannel: NSObject {
  static let name = "ai.viewbridge.vouch/app_settings"

  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: name, binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "deviceName":
        // iOS 16+ returns the generic model name here without an Apple
        // entitlement; good enough as a default the person can edit.
        result(UIDevice.current.name)
      case "biometryName":
        result(biometryName())
      case "isIgnoringBatteryOptimizations":
        result(true)
      case "requestIgnoreBatteryOptimizations", "openBatterySettings":
        if let url = URL(string: UIApplication.openSettingsURLString) {
          UIApplication.shared.open(url)
        }
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  /// "Face ID" or "Touch ID" by hardware, whether or not it is enrolled.
  private static func biometryName() -> String {
    let ctx = LAContext()
    _ = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    switch ctx.biometryType {
    case .faceID: return "Face ID"
    case .touchID: return "Touch ID"
    default: return "Face ID"
    }
  }
}
