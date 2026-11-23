import Flutter
import Foundation
import LocalAuthentication
import Security
import UIKit

/// The device keys, in the Secure Enclave. Private keys never leave it.
/// iOS twin of `android/.../DeviceKeyChannel.kt`: same channel name, same
/// methods, same error codes, so `lib/keys/device_key.dart` is unchanged.
///
/// Two kinds of key, chosen per alias by `requireUserAuth` at generation:
///  - a biometry-bound key (`.biometryCurrentSet`): every signature needs a
///    fresh Face ID or Touch ID match. There is no code path that signs with
///    it otherwise; the Secure Enclave refuses. A change to the enrolled
///    biometrics makes the key unusable for good (`key_invalidated`).
///  - a plain key: signs without a prompt, for calls nobody is looking at.
///    Usable after first unlock so a silent push can be answered while the
///    phone is locked.
///
/// iOS has no key attestation for app keys, so `attestationChain` is empty
/// and the server records the device as client-asserted (contract v0.2).
/// `strongBox` means "in the Secure Enclave" here.
///
/// Errors (channel error codes): no_key, cancelled, lockout, none_enrolled,
/// key_invalidated, not_authenticated, keystore.
final class DeviceKeyChannel: NSObject {
  static let name = "ai.viewbridge.vouch/device_key"

  private static let tagPrefix = "ai.viewbridge.vouch.key."
  private static let userAuthLabel = "vouch:user-auth"
  private static let plainLabel = "vouch:plain"

  /// X.509 SubjectPublicKeyInfo header for an uncompressed P-256 point.
  private static let p256SpkiPrefix: [UInt8] = [
    0x30, 0x59, 0x30, 0x13, 0x06, 0x07, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02, 0x01,
    0x06, 0x08, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07, 0x03, 0x42, 0x00,
  ]

  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: name, binaryMessenger: messenger)
    let handler = DeviceKeyChannel()
    channel.setMethodCallHandler { call, result in handler.handle(call, result) }
  }

  private struct ChannelError: Error {
    let code: String
    let message: String
  }

  private func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    // Key generation and signing block (the signing one on Face ID); keep
    // the UI thread free and answer on it.
    DispatchQueue.global(qos: .userInitiated).async {
      let outcome: Any?
      do {
        switch call.method {
        case "generate": outcome = try self.generate(args)
        case "exists": outcome = try self.exists(self.alias(args))
        case "delete":
          try self.delete(self.alias(args))
          outcome = nil
        case "publicKey": outcome = FlutterStandardTypedData(bytes: try self.publicKeySpki(self.alias(args)))
        case "attestationChain": outcome = [FlutterStandardTypedData]()
        case "info": outcome = try self.info(self.alias(args))
        case "biometricStatus": outcome = self.biometricStatus()
        case "sign": outcome = FlutterStandardTypedData(bytes: try self.sign(args))
        default:
          DispatchQueue.main.async { result(FlutterMethodNotImplemented) }
          return
        }
        DispatchQueue.main.async { result(outcome) }
      } catch let e as ChannelError {
        DispatchQueue.main.async { result(FlutterError(code: e.code, message: e.message, details: nil)) }
      } catch {
        DispatchQueue.main.async {
          result(FlutterError(code: "keystore", message: error.localizedDescription, details: nil))
        }
      }
    }
  }

  private func alias(_ args: [String: Any]) throws -> String {
    guard let a = args["alias"] as? String, !a.isEmpty else {
      throw ChannelError(code: "keystore", message: "alias is required")
    }
    return a
  }

  private func tag(_ alias: String) -> Data { Data((Self.tagPrefix + alias).utf8) }

  // MARK: generation

  private func generate(_ args: [String: Any]) throws -> [String: Any] {
    let alias = try alias(args)
    // The attestation challenge has no iOS equivalent; accepted and ignored.
    guard let requireUserAuth = args["requireUserAuth"] as? Bool else {
      throw ChannelError(code: "keystore", message: "requireUserAuth is required")
    }
    try delete(alias)

    var flags: SecAccessControlCreateFlags = [.privateKeyUsage]
    if requireUserAuth { flags.insert(.biometryCurrentSet) }
    // A decision needs the phone unlocked anyway; the transport key must
    // work from a background wake while the phone is locked.
    let accessible = requireUserAuth
      ? kSecAttrAccessibleWhenUnlockedThisDeviceOnly
      : kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    var acError: Unmanaged<CFError>?
    guard let access = SecAccessControlCreateWithFlags(nil, accessible, flags, &acError) else {
      throw ChannelError(code: "keystore", message: "access control: \(acError!.takeRetainedValue().localizedDescription)")
    }

    func attributes(secureEnclave: Bool) -> [String: Any] {
      var attrs: [String: Any] = [
        kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
        kSecAttrKeySizeInBits as String: 256,
        kSecPrivateKeyAttrs as String: [
          kSecAttrIsPermanent as String: true,
          kSecAttrApplicationTag as String: tag(alias),
          kSecAttrAccessControl as String: access,
          kSecAttrLabel as String: requireUserAuth ? Self.userAuthLabel : Self.plainLabel,
        ] as [String: Any],
      ]
      if secureEnclave { attrs[kSecAttrTokenID as String] = kSecAttrTokenIDSecureEnclave }
      return attrs
    }

    var secureEnclave = true
    var error: Unmanaged<CFError>?
    var key = SecKeyCreateRandomKey(attributes(secureEnclave: true) as CFDictionary, &error)
    if key == nil {
      #if targetEnvironment(simulator)
      // Older simulators have no Secure Enclave; a software key keeps the
      // flow testable there. Never on a device: a real key or nothing.
      secureEnclave = false
      error = nil
      key = SecKeyCreateRandomKey(attributes(secureEnclave: false) as CFDictionary, &error)
      #endif
    }
    guard key != nil else {
      throw ChannelError(code: "keystore", message: "key generation: \(describe(error))")
    }

    return [
      "publicKey": FlutterStandardTypedData(bytes: try publicKeySpki(alias)),
      "attestationChain": [FlutterStandardTypedData](),
      "strongBox": secureEnclave,
      "userAuthRequired": requireUserAuth,
    ]
  }

  // MARK: inspection

  private func baseQuery(_ alias: String) -> [String: Any] {
    [
      kSecClass as String: kSecClassKey,
      kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
      kSecAttrApplicationTag as String: tag(alias),
    ]
  }

  private func exists(_ alias: String) throws -> Bool {
    var q = baseQuery(alias)
    q[kSecReturnAttributes as String] = true
    q[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUISkip
    var item: CFTypeRef?
    let status = SecItemCopyMatching(q as CFDictionary, &item)
    switch status {
    case errSecSuccess, errSecInteractionNotAllowed: return true
    case errSecItemNotFound: return false
    default: throw ChannelError(code: "keystore", message: "exists: OSStatus \(status)")
    }
  }

  private func delete(_ alias: String) throws {
    let status = SecItemDelete(baseQuery(alias) as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw ChannelError(code: "keystore", message: "delete: OSStatus \(status)")
    }
  }

  /// The private key reference. [context] is attached for biometry-bound
  /// keys so the Face ID sheet shows our reason text.
  private func privateKey(_ alias: String, context: LAContext? = nil) throws -> SecKey {
    var q = baseQuery(alias)
    q[kSecReturnRef as String] = true
    if let context { q[kSecUseAuthenticationContext as String] = context }
    var item: CFTypeRef?
    let status = SecItemCopyMatching(q as CFDictionary, &item)
    guard status == errSecSuccess, let item else {
      if status == errSecItemNotFound { throw ChannelError(code: "no_key", message: "No key with alias \(alias)") }
      throw ChannelError(code: "keystore", message: "load key: OSStatus \(status)")
    }
    return item as! SecKey
  }

  private func attributes(_ alias: String) throws -> [String: Any] {
    var q = baseQuery(alias)
    q[kSecReturnAttributes as String] = true
    q[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUISkip
    var item: CFTypeRef?
    let status = SecItemCopyMatching(q as CFDictionary, &item)
    guard status == errSecSuccess, let attrs = item as? [String: Any] else {
      if status == errSecItemNotFound { throw ChannelError(code: "no_key", message: "No key with alias \(alias)") }
      throw ChannelError(code: "keystore", message: "attributes: OSStatus \(status)")
    }
    return attrs
  }

  private func publicKeySpki(_ alias: String) throws -> Data {
    let key = try privateKey(alias)
    guard let pub = SecKeyCopyPublicKey(key) else {
      throw ChannelError(code: "keystore", message: "no public key")
    }
    var error: Unmanaged<CFError>?
    guard let point = SecKeyCopyExternalRepresentation(pub, &error) as Data? else {
      throw ChannelError(code: "keystore", message: "export public key: \(describe(error))")
    }
    // X9.63 uncompressed point (0x04 || X || Y), 65 bytes for P-256.
    guard point.count == 65, point.first == 0x04 else {
      throw ChannelError(code: "keystore", message: "unexpected public key encoding (\(point.count) bytes)")
    }
    return Data(Self.p256SpkiPrefix) + point
  }

  private func info(_ alias: String) throws -> [String: Any] {
    let attrs = try attributes(alias)
    let userAuth = (attrs[kSecAttrLabel as String] as? String) == Self.userAuthLabel
    let tokenId = attrs[kSecAttrTokenID as String] as? String
    return [
      "strongBox": tokenId == (kSecAttrTokenIDSecureEnclave as String),
      "userAuthRequired": userAuth,
    ]
  }

  private func biometricStatus() -> String {
    var error: NSError?
    if LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
      return "available"
    }
    switch LAError.Code(rawValue: error?.code ?? 0) {
    case .biometryNotEnrolled: return "none_enrolled"
    case .biometryNotAvailable: return "no_hardware"
    case .biometryLockout: return "available"  // enrolled; sign() reports the lockout
    default: return "unavailable"
    }
  }

  // MARK: signing

  private func sign(_ args: [String: Any]) throws -> Data {
    let alias = try alias(args)
    guard let message = (args["message"] as? FlutterStandardTypedData)?.data else {
      throw ChannelError(code: "keystore", message: "message is required")
    }
    let title = args["title"] as? String ?? "Confirm"
    let subtitle = args["subtitle"] as? String
    let negative = args["negativeButton"] as? String ?? "Cancel"

    let userAuth = try info(alias)["userAuthRequired"] as? Bool ?? false
    var context: LAContext? = nil
    if userAuth {
      // Tell apart "locked out" and "nothing enrolled" before touching the
      // key: the Secure Enclave reports both as a plain auth failure.
      var laError: NSError?
      let ctx = LAContext()
      if !ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &laError) {
        switch LAError.Code(rawValue: laError?.code ?? 0) {
        case .biometryLockout: throw ChannelError(code: "lockout", message: "Too many failed attempts.")
        case .biometryNotEnrolled: throw ChannelError(code: "none_enrolled", message: "No Face ID or Touch ID enrolled.")
        default: throw ChannelError(code: "biometric", message: laError?.localizedDescription ?? "Biometrics unavailable.")
        }
      }
      ctx.localizedReason = subtitle.map { "\(title): \($0)" } ?? title
      ctx.localizedCancelTitle = negative
      ctx.localizedFallbackTitle = ""  // biometry only; no passcode fallback
      context = ctx
    }

    let key = try privateKey(alias, context: context)
    var error: Unmanaged<CFError>?
    guard let sig = SecKeyCreateSignature(key, .ecdsaSignatureMessageX962SHA256, message as CFData, &error) as Data? else {
      throw mapSignError(error, alias: alias, userAuth: userAuth)
    }
    return sig
  }

  private func mapSignError(_ error: Unmanaged<CFError>?, alias: String, userAuth: Bool) -> ChannelError {
    guard let err = error?.takeRetainedValue() else {
      return ChannelError(code: "keystore", message: "signing failed")
    }
    let ns = err as Error as NSError
    if ns.domain == LAErrorDomain {
      switch LAError.Code(rawValue: ns.code) {
      case .userCancel, .systemCancel, .appCancel: return ChannelError(code: "cancelled", message: "Cancelled.")
      case .biometryLockout: return ChannelError(code: "lockout", message: "Too many failed attempts.")
      case .biometryNotEnrolled: return ChannelError(code: "none_enrolled", message: "No Face ID or Touch ID enrolled.")
      default: return ChannelError(code: "biometric", message: ns.localizedDescription)
      }
    }
    switch OSStatus(ns.code) {
    case errSecUserCanceled: return ChannelError(code: "cancelled", message: "Cancelled.")
    case errSecAuthFailed where userAuth:
      // Biometrics are enrolled and not locked out (checked before signing),
      // yet the key refused: the enrolment changed since pairing. The key
      // is dead; remove it, as Android does.
      try? delete(alias)
      return ChannelError(code: "key_invalidated", message: "Face ID or Touch ID changed on this phone; pair again.")
    case errSecInteractionNotAllowed where userAuth:
      return ChannelError(code: "not_authenticated", message: "The key needs Face ID or Touch ID.")
    default:
      return ChannelError(code: "keystore", message: ns.localizedDescription)
    }
  }

  private func describe(_ error: Unmanaged<CFError>?) -> String {
    error?.takeRetainedValue().localizedDescription ?? "unknown error"
  }
}
