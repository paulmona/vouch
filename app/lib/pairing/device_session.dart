import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../api/cloudflare_access.dart';
import '../api/vouch_api_client.dart';
import '../keys/device_key.dart';
import '../keys/keystore_signer.dart';
import 'paired_device.dart';

/// Overridable in tests to inject a mock transport.
final httpClientProvider = Provider<http.Client Function()>(
  (ref) => http.Client.new,
);

final deviceKeyStoreProvider = Provider<DeviceKeyStore>(
  (ref) => DeviceKeyStore(),
);

/// The API for the paired server, signed by the transport key (no prompt).
/// Null when the phone is not paired.
final transportApiProvider = Provider<VouchApi?>((ref) {
  // Only the identity matters here. Watching the whole pairing would rebuild
  // the API (and re-run every status fetch) each time last contact changes.
  final (deviceId, serverUrl) = ref.watch(
    pairedDeviceProvider.select((p) => (p.value?.deviceId, p.value?.serverUrl)),
  );
  if (deviceId == null || serverUrl == null) return null;
  final api = VouchApi(
    serverUrl: serverUrl,
    deviceId: deviceId,
    signer: KeystoreSigner(
      store: ref.watch(deviceKeyStoreProvider),
      alias: DeviceKeyStore.transportAlias,
      prompt: const PromptText(title: 'Vouch'),
    ),
    inner: ref.watch(httpClientProvider)(),
  );
  ref.onDispose(api.close);
  return api;
});

/// Whether the key that signs decisions is still on the phone. Removing the
/// screen lock deletes it but not the transport key, so the server still
/// answers and only a decision would fail. Rechecked whenever the server
/// status is (on resume, on pull to refresh).
final decisionKeyPresentProvider = FutureProvider.autoDispose<bool>((ref) {
  ref.watch(deviceStatusProvider);
  return ref.watch(deviceKeyStoreProvider).exists(DeviceKeyStore.decisionAlias);
});

/// Result of asking the server about this device.
sealed class DeviceStatus {
  const DeviceStatus();
}

class DeviceOnline extends DeviceStatus {
  const DeviceOnline(this.device);
  final Device device;
}

/// The server answered but no longer knows this device (unpaired there).
class DeviceUnpaired extends DeviceStatus {
  const DeviceUnpaired();
}

class DeviceUnreachable extends DeviceStatus {
  const DeviceUnreachable(this.message);
  final String message;
}

/// `GET /v1/devices/me`: refreshes last contact and the server's policy.
/// Invalidate it on app resume or pull-to-refresh.
final deviceStatusProvider = FutureProvider.autoDispose<DeviceStatus?>((
  ref,
) async {
  final api = ref.watch(transportApiProvider);
  if (api == null) return null;
  final Device? d;
  try {
    d = await api.devices.getDevice();
  } on ApiException catch (e) {
    if (isAccessBlocked(e)) {
      return const DeviceUnreachable(accessBlockedMessage);
    }
    if (e.innerException != null) {
      return DeviceUnreachable("Couldn't reach the server.");
    }
    if (e.code == 401) return const DeviceUnpaired();
    return DeviceUnreachable('The server answered ${e.code}.');
  } on http.ClientException catch (e) {
    if (isAccessBlocked(e)) {
      return const DeviceUnreachable(accessBlockedMessage);
    }
    return DeviceUnreachable("Couldn't reach the server: ${e.message}");
  }
  if (d == null) {
    return const DeviceUnreachable('Empty answer from the server.');
  }
  final notifier = ref.read(pairedDeviceProvider.notifier);
  await notifier.applyServer(
    lastContactAt: DateTime.now(),
    requireUserAuth: d.policy.requireUserAuth,
    userAuthBound: d.userAuthBound.toString(),
    rekeyRequired: d.rekeyRequired ?? false,
    pushEnabled: d.pushEnabled ?? true,
  );
  return DeviceOnline(d);
});
