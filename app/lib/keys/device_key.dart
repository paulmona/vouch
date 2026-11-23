import 'package:flutter/services.dart';

/// Dart side of the Android `DeviceKeyChannel` (see
/// `android/app/src/main/kotlin/ai/viewbridge/vouch/DeviceKeyChannel.kt`).
///
/// Private keys live in the Android Keystore and never come across this
/// channel: only public keys, attestation chains and signatures do.
class DeviceKeyStore {
  DeviceKeyStore({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName);

  static const channelName = 'ai.viewbridge.vouch/device_key';

  /// The attested, fingerprint-bound key that signs decisions.
  static const decisionAlias = 'vouch.decision';

  /// The plain key that signs everything else (pending contract change).
  static const transportAlias = 'vouch.transport';

  final MethodChannel _channel;

  /// Generates a fresh P-256 key (replacing any key with that alias).
  /// [challenge] goes into the attestation: SHA-256 of the setup token.
  Future<GeneratedKey> generate({
    required String alias,
    required Uint8List challenge,
    required bool requireUserAuth,
  }) async {
    final r = (await _invoke<Map<Object?, Object?>>('generate', {
      'alias': alias,
      'challenge': challenge,
      'requireUserAuth': requireUserAuth,
    }))!;
    return GeneratedKey(
      publicKeySpki: r['publicKey']! as Uint8List,
      attestationChain: (r['attestationChain']! as List<Object?>)
          .cast<Uint8List>(),
      strongBox: r['strongBox']! as bool,
      userAuthRequired: r['userAuthRequired']! as bool,
    );
  }

  Future<bool> exists(String alias) async =>
      (await _invoke<bool>('exists', {'alias': alias}))!;

  Future<void> delete(String alias) =>
      _invoke<void>('delete', {'alias': alias});

  Future<Uint8List> publicKeySpki(String alias) async =>
      (await _invoke<Uint8List>('publicKey', {'alias': alias}))!;

  Future<List<Uint8List>> attestationChain(String alias) async =>
      (await _invoke<List<Object?>>('attestationChain', {
        'alias': alias,
      }))!.cast<Uint8List>();

  Future<KeyInfo> info(String alias) async {
    final r = (await _invoke<Map<Object?, Object?>>('info', {'alias': alias}))!;
    return KeyInfo(
      strongBox: r['strongBox']! as bool,
      userAuthRequired: r['userAuthRequired']! as bool,
    );
  }

  Future<BiometricStatus> biometricStatus() async {
    final s = await _invoke<String>('biometricStatus', {});
    return switch (s) {
      'available' => BiometricStatus.available,
      'none_enrolled' => BiometricStatus.noneEnrolled,
      'no_hardware' => BiometricStatus.noHardware,
      _ => BiometricStatus.unavailable,
    };
  }

  /// Signs [message] (ECDSA P-256 / SHA-256, DER). For a fingerprint-bound
  /// key this shows the system prompt with [prompt]'s texts; the signature
  /// only exists if the fingerprint matched.
  Future<Uint8List> sign({
    required String alias,
    required Uint8List message,
    required PromptText prompt,
  }) async => (await _invoke<Uint8List>('sign', {
    'alias': alias,
    'message': message,
    'title': prompt.title,
    'subtitle': prompt.subtitle,
    'negativeButton': prompt.negativeButton,
  }))!;

  Future<T?> _invoke<T>(String method, Map<String, Object?> args) async {
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on PlatformException catch (e) {
      throw DeviceKeyException.fromPlatform(e);
    }
  }
}

class GeneratedKey {
  const GeneratedKey({
    required this.publicKeySpki,
    required this.attestationChain,
    required this.strongBox,
    required this.userAuthRequired,
  });

  final Uint8List publicKeySpki;

  /// Leaf first, DER. Empty would mean no attestation (never on Android).
  final List<Uint8List> attestationChain;
  final bool strongBox;
  final bool userAuthRequired;
}

class KeyInfo {
  const KeyInfo({required this.strongBox, required this.userAuthRequired});
  final bool strongBox;
  final bool userAuthRequired;
}

enum BiometricStatus { available, noneEnrolled, noHardware, unavailable }

/// What the system fingerprint sheet says.
class PromptText {
  const PromptText({
    required this.title,
    this.subtitle,
    this.negativeButton = 'Cancel',
  });

  final String title;
  final String? subtitle;
  final String negativeButton;

  /// The decision prompt from the brief: "Confirm approval", naming the
  /// agent and site.
  factory PromptText.confirmApproval({
    required String agent,
    required String site,
  }) => PromptText(title: 'Confirm approval', subtitle: '$agent at $site');
}

enum DeviceKeyError {
  /// No key with that alias; pair first.
  noKey,

  /// The person dismissed the fingerprint sheet. Nothing was signed.
  cancelled,

  /// Too many failed attempts; the sensor is locked for a while.
  lockout,

  /// No fingerprint enrolled on the phone.
  noneEnrolled,

  /// The enrolled fingerprints changed; the key was destroyed. Re-pair.
  keyInvalidated,

  /// The Keystore refused to sign without a fresh fingerprint (should not
  /// happen through the prompt path; proves the binding if it ever does).
  notAuthenticated,

  /// Any other biometric or Keystore failure; [DeviceKeyException.message].
  other,
}

class DeviceKeyException implements Exception {
  DeviceKeyException(this.error, this.message, {this.code});

  factory DeviceKeyException.fromPlatform(PlatformException e) {
    final error = switch (e.code) {
      'no_key' => DeviceKeyError.noKey,
      'cancelled' => DeviceKeyError.cancelled,
      'lockout' => DeviceKeyError.lockout,
      'none_enrolled' => DeviceKeyError.noneEnrolled,
      'key_invalidated' => DeviceKeyError.keyInvalidated,
      'not_authenticated' => DeviceKeyError.notAuthenticated,
      _ => DeviceKeyError.other,
    };
    return DeviceKeyException(error, e.message ?? e.code, code: e.code);
  }

  final DeviceKeyError error;
  final String message;
  final String? code;

  @override
  String toString() => 'DeviceKeyException(${error.name}: $message)';
}
