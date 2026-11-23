import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // A request push is an alert iOS shows itself, under an identifier the app
  // never sees, so the Dart side's cancel-by-id cannot reach it. A clear push
  // removes it here, matched on the request_id Firebase copies into userInfo.
  override func application(
    _ application: UIApplication,
    didReceiveRemoteNotification userInfo: [AnyHashable: Any],
    fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
  ) {
    if userInfo["kind"] as? String == "clear", let requestId = userInfo["request_id"] as? String {
      let center = UNUserNotificationCenter.current()
      center.getDeliveredNotifications { delivered in
        let ids = delivered
          .filter {
            $0.request.content.userInfo["kind"] as? String == "request"
              && $0.request.content.userInfo["request_id"] as? String == requestId
          }
          .map { $0.request.identifier }
        if !ids.isEmpty { center.removeDeliveredNotifications(withIdentifiers: ids) }
      }
    }
    super.application(
      application, didReceiveRemoteNotification: userInfo, fetchCompletionHandler: completionHandler)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // Vouch's own channels: the Secure Enclave keys, pair links, the
    // contact picker and the few settings calls. Same channel names as the Android side.
    let messenger = engineBridge.applicationRegistrar.messenger()
    DeviceKeyChannel.register(with: messenger)
    AppSettingsChannel.register(with: messenger)
    PairLinkChannel.register(with: messenger)
    ContactPickerChannel.register(with: messenger)
  }
}
