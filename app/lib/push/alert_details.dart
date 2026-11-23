import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../alerts/alerts.dart';
import '../api/vouch_api_client.dart';
import '../keys/device_key.dart';
import '../keys/keystore_signer.dart';
import '../pairing/paired_device.dart';

/// The words behind an `alert` push: `GET /v1/alerts/{id}`, signed with the
/// transport key (no prompt). The push itself never carries them. Built from
/// the stored pairing so it also runs in the Firebase background isolate.
class AlertDetails {
  AlertDetails({
    PairedDeviceStore? pairing,
    DeviceKeyStore? keys,
    http.Client Function()? httpClient,
  }) : _pairing = pairing ?? PairedDeviceStore(),
       _keys = keys ?? DeviceKeyStore(),
       _httpClient = httpClient ?? http.Client.new;

  final PairedDeviceStore _pairing;
  final DeviceKeyStore _keys;
  final http.Client Function() _httpClient;

  /// Null when unpaired, unreachable, or the alert is unknown: the caller
  /// then shows a generic notification rather than nothing.
  Future<Alert?> fetch(String alertId) async {
    final paired = await _pairing.load();
    if (paired == null) return null;
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
      return await api.alerts.getAlert(alertId);
    } on ApiException catch (e) {
      debugPrint('Vouch: alert details refused (${e.code})');
    } on Object catch (e) {
      debugPrint('Vouch: alert details failed (${e.runtimeType})');
    } finally {
      api.close();
    }
    return null;
  }

  /// Notification text for an alert; the severity leads the title so a
  /// critical one reads as such at a glance.
  static ({String title, String body}) textFor(Alert a) => (
    title: switch (a.severity) {
      AlertSeverityEnum.critical => 'Critical: ${a.shownTitle}',
      AlertSeverityEnum.warning => 'Warning: ${a.shownTitle}',
      _ => a.shownTitle,
    },
    body: a.shownBody,
  );
}
