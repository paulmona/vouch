import Flutter
import Foundation
import Network

/// Hands `vouch://pair?...` links to Dart: the one the app was launched
/// with (`initialLink`, read once) and any that arrive while it runs
/// (`link` calls). Only the link text crosses; the Dart side parses it and
/// asks before pairing, so a tapped link never pairs on its own.
///
/// Links come in through the scene delegate. At a cold start the channel
/// can exist before Dart has set its handler, and a call made then is
/// dropped. So every link waits in `pending` until Dart has asked
/// for `initialLink`; only after that are links pushed with `link`.
enum PairLinkChannel {
  static let name = "ai.viewbridge.vouch/pair_link"
  private static var channel: FlutterMethodChannel?
  private static var pending: String?
  private static var dartListening = false

  static func register(with messenger: FlutterBinaryMessenger) {
    let ch = FlutterMethodChannel(name: name, binaryMessenger: messenger)
    ch.setMethodCallHandler { call, result in
      switch call.method {
      case "initialLink":
        result(pending)
        pending = nil
        dartListening = true
      case "askLocalNetwork":
        if let args = call.arguments as? [String: Any],
          let host = args["host"] as? String,
          let port = args["port"] as? Int,
          let p = NWEndpoint.Port(rawValue: UInt16(clamping: port))
        {
          askLocalNetwork(host: host, port: p)
        }
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    channel = ch
  }

  static func deliver(_ urls: Set<UIOpenURLContext>) {
    for ctx in urls { deliver(ctx.url) }
  }

  static func deliver(_ url: URL) {
    guard url.scheme == "vouch", url.host == "pair" else { return }
    if dartListening, let ch = channel {
      ch.invokeMethod("link", arguments: url.absoluteString)
    } else {
      pending = url.absoluteString
    }
  }

  /// Pairing talks to the server with Dart's sockets, and iOS never shows
  /// the Local Network prompt for those: it just blocks them. A
  /// Network.framework connection to the same address does bring up the
  /// prompt, so one is opened before pairing and dropped once it settles.
  private static func askLocalNetwork(host: String, port: NWEndpoint.Port) {
    let conn = NWConnection(host: NWEndpoint.Host(host), port: port, using: .tcp)
    conn.stateUpdateHandler = { state in
      switch state {
      case .ready, .failed:
        conn.cancel()
      case .cancelled:
        conn.stateUpdateHandler = nil
      default:
        break
      }
    }
    conn.start(queue: .global())
    DispatchQueue.global().asyncAfter(deadline: .now() + 30) { conn.cancel() }
  }
}
