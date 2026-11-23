import 'dart:async';

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../push/contact_watchdog.dart';

/// What the app keeps about its pairing. Nothing here is secret: the keys
/// stay in the Keystore and the device id is public to the server anyway.
class PairedDevice {
  const PairedDevice({
    required this.deviceId,
    required this.serverUrl,
    required this.serverName,
    required this.requireUserAuth,
    required this.userAuthBound,
    required this.pairedAt,
    this.lastContactAt,
    this.rekeyRequired = false,
    this.pushEnabled = true,
  });

  final String deviceId;
  final Uri serverUrl;
  final String serverName;

  /// Server policy: decisions need a fingerprint for every use.
  final bool requireUserAuth;

  /// `attested`, `client_asserted` or `none`: what the server knows about
  /// the decision key.
  final String userAuthBound;
  final DateTime pairedAt;

  /// Last time the app heard from the server (any successful call).
  final DateTime? lastContactAt;

  /// The server's policy changed and this key no longer meets it.
  final bool rekeyRequired;

  /// False when the server has no push set up: requests only show while
  /// the app is open. Older servers don't say, which means push.
  final bool pushEnabled;

  PairedDevice copyWith({
    DateTime? lastContactAt,
    bool? requireUserAuth,
    String? userAuthBound,
    bool? rekeyRequired,
    bool? pushEnabled,
  }) => PairedDevice(
    deviceId: deviceId,
    serverUrl: serverUrl,
    serverName: serverName,
    requireUserAuth: requireUserAuth ?? this.requireUserAuth,
    userAuthBound: userAuthBound ?? this.userAuthBound,
    pairedAt: pairedAt,
    lastContactAt: lastContactAt ?? this.lastContactAt,
    rekeyRequired: rekeyRequired ?? this.rekeyRequired,
    pushEnabled: pushEnabled ?? this.pushEnabled,
  );

  Map<String, Object?> toJson() => {
    'device_id': deviceId,
    'server_url': serverUrl.toString(),
    'server_name': serverName,
    'require_user_auth': requireUserAuth,
    'user_auth_bound': userAuthBound,
    'paired_at': pairedAt.toUtc().toIso8601String(),
    'last_contact_at': lastContactAt?.toUtc().toIso8601String(),
    'rekey_required': rekeyRequired,
    'push_enabled': pushEnabled,
  };

  static PairedDevice fromJson(Map<String, Object?> j) => PairedDevice(
    deviceId: j['device_id']! as String,
    serverUrl: Uri.parse(j['server_url']! as String),
    serverName: j['server_name']! as String,
    requireUserAuth: j['require_user_auth']! as bool,
    userAuthBound: j['user_auth_bound']! as String,
    pairedAt: DateTime.parse(j['paired_at']! as String),
    lastContactAt: switch (j['last_contact_at']) {
      final String s => DateTime.parse(s),
      _ => null,
    },
    rekeyRequired: j['rekey_required'] == true,
    pushEnabled: j['push_enabled'] != false,
  );
}

/// Persistence for [PairedDevice] in SharedPreferences.
class PairedDeviceStore {
  static const key = 'paired_device';

  Future<PairedDevice?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString(key);
    if (s == null) return null;
    try {
      return PairedDevice.fromJson(jsonDecode(s) as Map<String, Object?>);
    } on Object {
      return null;
    }
  }

  Future<void> save(PairedDevice d) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, jsonEncode(d.toJson()));
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
  }
}

final pairedDeviceStoreProvider = Provider<PairedDeviceStore>(
  (ref) => PairedDeviceStore(),
);

/// The current pairing, or null when the phone is not paired.
class PairedDeviceNotifier extends AsyncNotifier<PairedDevice?> {
  @override
  Future<PairedDevice?> build() => ref.read(pairedDeviceStoreProvider).load();

  Future<void> set(PairedDevice d) async {
    // State first: two updates in flight (the device status and a request
    // fetch both report contact) each build on the latest, instead of the
    // second overwriting the first from a stale copy.
    state = AsyncData(d);
    await ref.read(pairedDeviceStoreProvider).save(d);
  }

  /// Applies what the server just said about this device.
  Future<void> applyServer({
    DateTime? lastContactAt,
    bool? requireUserAuth,
    String? userAuthBound,
    bool? rekeyRequired,
    bool? pushEnabled,
  }) async {
    final d = state.value;
    if (d == null) return;
    final push = pushEnabled ?? d.pushEnabled;
    if (!push) {
      // Without push the server can't reach the phone between visits, so
      // a day of silence is normal, not a sign the server is down.
      unawaited(ref.read(contactWatchdogProvider).stop());
    } else if (lastContactAt != null) {
      // Heard from the server: push the 26 h fallback out again.
      unawaited(
        ref
            .read(contactWatchdogProvider)
            .heard(at: lastContactAt, serverName: d.serverName),
      );
    }
    await set(
      d.copyWith(
        lastContactAt: lastContactAt,
        requireUserAuth: requireUserAuth,
        userAuthBound: userAuthBound,
        rekeyRequired: rekeyRequired,
        pushEnabled: pushEnabled,
      ),
    );
  }

  Future<void> clear() async {
    await ref.read(pairedDeviceStoreProvider).clear();
    await ref.read(contactWatchdogProvider).stop();
    state = const AsyncData(null);
  }
}

final pairedDeviceProvider =
    AsyncNotifierProvider<PairedDeviceNotifier, PairedDevice?>(
      PairedDeviceNotifier.new,
    );
