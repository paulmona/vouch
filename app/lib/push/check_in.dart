import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../api/vouch_api_client.dart';
import '../keys/device_key.dart';
import '../keys/keystore_signer.dart';
import '../pairing/device_session.dart';
import '../pairing/paired_device.dart';
import 'contact_watchdog.dart';

/// `POST /v1/devices/me/checkin`: the answer to a heartbeat push, and the
/// app-open check-in the contract asks for. Signed with the transport key,
/// so there is no prompt.
///
/// Built from the stored pairing rather than Riverpod, because it also runs
/// in the Firebase background isolate. A heartbeat the phone could not answer
/// at the time (no network, key unavailable in that isolate) is kept and sent
/// with the next check-in, so the server still learns the push arrived.
class CheckInService {
  CheckInService({
    PairedDeviceStore? pairing,
    DeviceKeyStore? keys,
    http.Client Function()? httpClient,
    Future<SharedPreferences> Function()? prefs,
    this.watchdog,
  }) : _pairing = pairing ?? PairedDeviceStore(),
       _keys = keys ?? DeviceKeyStore(),
       _httpClient = httpClient ?? http.Client.new,
       _prefs = prefs ?? SharedPreferences.getInstance;

  /// Re-armed on a successful check-in (a contact). Null in the background
  /// isolate, where the push handler already counted the contact.
  final ContactWatchdog? watchdog;

  static const pendingKey = 'pending_heartbeat_id';

  final PairedDeviceStore _pairing;
  final DeviceKeyStore _keys;
  final http.Client Function() _httpClient;
  final Future<SharedPreferences> Function() _prefs;

  /// True when the server recorded it. [heartbeatId] is null for an app-open
  /// check-in; a heartbeat still owed from earlier is sent in its place.
  Future<bool> checkIn({String? heartbeatId}) async {
    final paired = await _pairing.load();
    if (paired == null) return false;
    final prefs = await _prefs();
    final id = heartbeatId ?? prefs.getString(pendingKey);

    final api = VouchApi(
      serverUrl: paired.serverUrl,
      deviceId: paired.deviceId,
      signer: KeystoreSigner(
        store: _keys,
        alias: DeviceKeyStore.transportAlias,
        prompt: const PromptText(title: 'Vouch'),
      ),
      inner: _httpClient(),
    );
    try {
      await api.devices.checkIn(CheckInRequest(heartbeatId: id));
      if (id != null) await prefs.remove(pendingKey);
      // Without push, a day without contact is normal: nothing to re-arm.
      if (paired.pushEnabled) {
        await watchdog?.heard(serverName: paired.serverName);
      }
      return true;
    } on ApiException catch (e) {
      debugPrint('Vouch: check-in refused (${e.code})');
    } on Object catch (e) {
      // Connection failures, and the Keystore channel being absent in the
      // background isolate, land here.
      debugPrint('Vouch: check-in failed (${e.runtimeType})');
    } finally {
      api.close();
    }
    if (id != null) await prefs.setString(pendingKey, id);
    return false;
  }
}

/// The app's check-in, sharing the key store and HTTP client the rest of the
/// app is built with (tests swap them).
final checkInServiceProvider = Provider<CheckInService>(
  (ref) => CheckInService(
    keys: ref.watch(deviceKeyStoreProvider),
    httpClient: ref.watch(httpClientProvider),
    watchdog: ref.watch(contactWatchdogProvider),
  ),
);
