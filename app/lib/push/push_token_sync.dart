import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/vouch_api_client.dart';
import '../pairing/device_session.dart';
import '../pairing/paired_device.dart';
import 'push_service.dart';

/// Keeps the server's copy of this device's Firebase token current: Firebase
/// rotates tokens, and a stale one means missed requests. Runs for as long
/// as the app does; the call is signed by the transport key, so no prompt.
class PushTokenSync {
  PushTokenSync(
    this._ref, {
    Stream<String>? tokens,
    String? Function()? current,
  }) : _tokens = tokens ?? PushService.instance.onTokenRefresh,
       _current = current ?? (() => PushService.instance.token);

  final Ref _ref;
  final Stream<String> _tokens;

  /// The token held right now, if any: it may have arrived before anyone
  /// listened (PushService fetches it before the app root exists).
  final String? Function() _current;
  StreamSubscription<String>? _sub;
  String? _lastSent;
  String? _inFlight;

  void start() {
    if (_sub != null) return;
    _sub = _tokens.listen((t) => unawaited(send(t)));
    final now = _current();
    if (now != null) unawaited(send(now));
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
  }

  /// Sends [token] if the phone is paired and it differs from the last one
  /// sent. Returns true when the server took it.
  Future<bool> send(String token) async {
    if (token == _lastSent || token == _inFlight) return true;
    var api = _ref.read(transportApiProvider);
    if (api == null) {
      // The pairing may still be loading from disk at startup.
      await _ref.read(pairedDeviceProvider.future);
      api = _ref.read(transportApiProvider);
    }
    if (api == null) return false;
    _inFlight = token;
    try {
      await api.devices.updatePushToken(
        UpdatePushTokenRequest(pushToken: token),
      );
      _lastSent = token;
      return true;
    } on ApiException catch (e) {
      // Not logging the token. Firebase will rotate again; the next app open
      // retries through pairedDeviceProvider's status refresh anyway.
      debugPrint('Vouch: push token update refused (${e.code})');
      return false;
    } catch (e) {
      debugPrint('Vouch: push token update failed (${e.runtimeType})');
      return false;
    } finally {
      _inFlight = null;
    }
  }
}

final pushTokenSyncProvider = Provider<PushTokenSync>((ref) {
  final sync = PushTokenSync(ref)..start();
  ref.onDispose(sync.stop);
  return sync;
});
