import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  // vouch://pair links: at launch (connectionOptions) and while running.
  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    PairLinkChannel.deliver(connectionOptions.urlContexts)
  }

  override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    super.scene(scene, openURLContexts: URLContexts)
    PairLinkChannel.deliver(URLContexts)
  }
}
