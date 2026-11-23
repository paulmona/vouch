import 'dart:convert';
import 'dart:io' as io;

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../api/canonical.dart';
import '../api/cloudflare_access.dart';
import '../api/vouch_api_client.dart';
import '../keys/device_key.dart';
import '../keys/keystore_signer.dart';
import '../platform/biometry.dart';
import 'pair_link.dart';
import 'paired_device.dart';

enum PairingStep { creatingKeys, confirming, registering, done }

enum PairingError {
  /// No fingerprint enrolled (or no sensor): the decision key cannot exist.
  biometricsUnavailable,

  /// The person dismissed the "Confirm pairing" prompt. Nothing was sent.
  cancelled,

  /// Firebase has not issued a push token yet.
  noPushToken,

  /// The setup code expired or was already used.
  invalidToken,

  /// Cloudflare Access stopped the request.
  accessBlocked,

  /// The server refused the key attestation.
  attestationRefused,

  /// The server needs a fingerprint-bound key and this one is not.
  policyRequiresUserAuth,

  /// The phone's clock is off by more than a minute.
  clockSkew,

  /// Could not reach the server.
  network,

  /// Anything else the server said; see [PairingException.message].
  server,
}

class PairingException implements Exception {
  const PairingException(this.error, this.message);
  final PairingError error;

  /// Plain English, safe to show.
  final String message;

  @override
  String toString() => 'PairingException(${error.name}: $message)';
}

/// Pairs this phone with a server: two Keystore keys, the decision key's
/// proof under one fingerprint prompt, and `POST /v1/devices/pair` signed by
/// the transport key. On success the pairing is saved.
class PairingService {
  PairingService({
    required this.keys,
    required this.store,
    required this.pushToken,
    http.Client Function()? httpClient,
    DateTime Function()? now,
    bool? retryLocalNetwork,
    this.retryEvery = const Duration(seconds: 2),
    Future<void> Function(Uri server)? askLocalNetwork,
  }) : _httpClient = httpClient ?? _defaultClient,
       _now = now ?? DateTime.now,
       _retryLocalNetwork = retryLocalNetwork ?? io.Platform.isIOS,
       _askLocalNetwork =
           askLocalNetwork ??
           (io.Platform.isIOS ? _askLocalNetworkIos : (_) async {});

  /// A connect that iOS holds back (Local Network not yet allowed) can hang
  /// for minutes; give up quickly so the retries below get their turn.
  static http.Client _defaultClient() =>
      IOClient(io.HttpClient()..connectionTimeout = connectTimeout);
  static const connectTimeout = Duration(seconds: 5);

  /// Dart's sockets don't make iOS show the Local Network prompt; a
  /// Network.framework connection does. Native side: PairLinkChannel.swift.
  static Future<void> _askLocalNetworkIos(Uri server) => const MethodChannel(
    'ai.viewbridge.vouch/pair_link',
  ).invokeMethod('askLocalNetwork', {'host': server.host, 'port': server.port});

  final DeviceKeyStore keys;
  final PairedDeviceStore store;

  /// The current Firebase token, or null if none yet.
  final Future<String?> Function() pushToken;
  final http.Client Function() _httpClient;
  final DateTime Function() _now;

  /// iOS asks for Local Network permission on the first request to a LAN
  /// address, and that request fails while the prompt is up. So a pair
  /// request to a local address that never reached the server is retried
  /// for a while; it hasn't used the setup code.
  final bool _retryLocalNetwork;
  final Future<void> Function(Uri server) _askLocalNetwork;
  final Duration retryEvery;
  static const localNetworkRetries = 7;

  /// The addresses iOS's Local Network permission covers.
  static bool isLocalHost(String host) => PairLink.isLanHost(host);

  static const proofPrefix = 'vouch-pair-v1\n';

  /// Raw 32-byte SHA-256 of the token's UTF-8 bytes: the attestation
  /// challenge for both keys.
  static Uint8List challenge(String setupToken) =>
      Uint8List.fromList(sha256.convert(utf8.encode(setupToken)).bytes);

  static Uint8List proofMessage(String setupToken) =>
      Uint8List.fromList(utf8.encode('$proofPrefix$setupToken'));

  Future<PairedDevice> pair(
    PairLink link, {
    required String deviceName,
    bool sendAttestation = true,
    bool sendPendingAccessToken = false,
    void Function(PairingStep step)? onStep,
  }) async {
    onStep?.call(PairingStep.creatingKeys);
    final token = await pushToken();
    if (token == null || token.isEmpty) {
      throw const PairingException(
        PairingError.noPushToken,
        "Push isn't ready yet. Check the connection and try again.",
      );
    }
    final bio = await keys.biometricStatus();
    if (bio != BiometricStatus.available) {
      throw PairingException(
        PairingError.biometricsUnavailable,
        bio == BiometricStatus.noneEnrolled
            ? '${Biometry.setupHint} first. '
                  'Vouch needs it to confirm approvals.'
            : 'This phone has no usable ${Biometry.name} sensor.',
      );
    }
    final ch = challenge(link.token);
    final transport = await keys.generate(
      alias: DeviceKeyStore.transportAlias,
      challenge: ch,
      requireUserAuth: false,
    );
    final decision = await keys.generate(
      alias: DeviceKeyStore.decisionAlias,
      challenge: ch,
      requireUserAuth: true,
    );

    onStep?.call(PairingStep.confirming);
    final Uint8List proof;
    try {
      proof = await keys.sign(
        alias: DeviceKeyStore.decisionAlias,
        message: proofMessage(link.token),
        prompt: PromptText(
          title: 'Confirm pairing',
          subtitle: link.server.host,
        ),
      );
    } on DeviceKeyException catch (e) {
      throw switch (e.error) {
        DeviceKeyError.cancelled => const PairingException(
          PairingError.cancelled,
          'Pairing was not confirmed. Nothing was sent.',
        ),
        DeviceKeyError.noneEnrolled => PairingException(
          PairingError.biometricsUnavailable,
          '${Biometry.setupHint} first.',
        ),
        _ => PairingException(PairingError.server, e.message),
      };
    }

    onStep?.call(PairingStep.registering);
    // A token entered before the code was scanned goes only to a host the
    // person was shown and confirmed on screen; a link's host alone is not
    // enough, since anyone can make a QR code.
    if (sendPendingAccessToken) {
      await CloudflareAccessStore.instance.bindPending(link.server);
    }
    final api = VouchApi(
      serverUrl: link.server,
      signer: KeystoreSigner(
        store: keys,
        alias: DeviceKeyStore.transportAlias,
        prompt: const PromptText(title: 'Vouch'),
      ),
      inner: _httpClient(),
    );
    final b64 = Canonical.base64UrlNoPad;
    final body = PairRequest(
      setupToken: link.token,
      publicKey: b64(decision.publicKeySpki),
      attestationChain: sendAttestation
          ? decision.attestationChain.map(b64).toList()
          : const [],
      decisionKeyProof: b64(proof),
      transportPublicKey: b64(transport.publicKeySpki),
      transportAttestationChain: sendAttestation
          ? transport.attestationChain.map(b64).toList()
          : const [],
      pushToken: token,
      name: deviceName,
      platform: io.Platform.isIOS ? Platform.ios : Platform.android,
    );

    final PairResponse? r;
    try {
      r = await _pairWithRetry(api, body, link.server);
    } on ApiException catch (e) {
      throw _fromApi(e);
    } on http.ClientException catch (e) {
      if (isAccessBlocked(e)) {
        throw const PairingException(
          PairingError.accessBlocked,
          accessBlockedMessage,
        );
      }
      throw PairingException(
        PairingError.network,
        "Couldn't reach ${link.server.host}: ${e.message}",
      );
    } finally {
      api.close();
    }
    if (r == null) {
      throw const PairingException(
        PairingError.server,
        'The server gave an empty answer.',
      );
    }

    final paired = PairedDevice(
      deviceId: r.deviceId,
      serverUrl: link.server,
      serverName: r.serverName,
      requireUserAuth: r.policy.requireUserAuth,
      userAuthBound: r.userAuthBound.toString(),
      pairedAt: _now(),
      lastContactAt: _now(),
      pushEnabled: r.pushEnabled ?? true,
    );
    await store.save(paired);
    onStep?.call(PairingStep.done);
    return paired;
  }

  Future<PairResponse?> _pairWithRetry(
    VouchApi api,
    PairRequest body,
    Uri server,
  ) async {
    final retries = _retryLocalNetwork && isLocalHost(server.host)
        ? localNetworkRetries
        : 0;
    if (retries > 0) {
      try {
        await _askLocalNetwork(server);
      } on Object {
        // Only a nudge for the prompt; the request below decides.
      }
    }
    for (var attempt = 0; ; attempt++) {
      try {
        return await api.devices.pairDevice(body);
      } on Object catch (e) {
        if (attempt >= retries || !_neverArrived(e)) rethrow;
      }
      await Future<void>.delayed(retryEvery);
    }
  }

  /// The connection failed (http's socket errors implement
  /// [io.SocketException]); a server answer, even an error, never counts.
  static bool _neverArrived(Object e) =>
      e is io.SocketException ||
      (e is ApiException && e.innerException is io.SocketException);

  static PairingException _fromApi(ApiException e) {
    // The generated client wraps connection failures as an ApiException
    // carrying the original error.
    if (isAccessBlocked(e)) {
      return const PairingException(
        PairingError.accessBlocked,
        accessBlockedMessage,
      );
    }
    if (e.innerException != null) {
      return PairingException(
        PairingError.network,
        "Couldn't reach the server: ${e.innerException}",
      );
    }
    String? code;
    String? message;
    try {
      final j = jsonDecode(e.message ?? '') as Map<String, Object?>;
      code = j['code'] as String?;
      message = j['message'] as String?;
    } on Object {
      // Not a JSON error body; fall through.
    }
    return switch (code) {
      'invalid_setup_token' => PairingException(
        PairingError.invalidToken,
        message ?? 'This pairing code expired or was already used.',
      ),
      'attestation_failed' => PairingException(
        PairingError.attestationRefused,
        message ?? "The server refused this phone's key attestation.",
      ),
      'policy_requires_user_auth' => PairingException(
        PairingError.policyRequiresUserAuth,
        message ?? 'This server needs a ${Biometry.bound} key.',
      ),
      'clock_skew' => PairingException(
        PairingError.clockSkew,
        message ?? "This phone's clock is too far off. Set it to automatic.",
      ),
      _ => PairingException(
        PairingError.server,
        message ?? 'The server refused the pairing (HTTP ${e.code}).',
      ),
    };
  }
}
