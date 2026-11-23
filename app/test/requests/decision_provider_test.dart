import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vouch/keys/device_key.dart';
import 'package:vouch/pairing/device_session.dart';
import 'package:vouch/pairing/paired_device.dart';
import 'package:vouch/requests/decision_service.dart';

import '../helpers/fake_keys.dart';

/// the app refreshes device status and the pending list when it
/// resumes after the fingerprint prompt, and both update "last contact".
/// The decision service in the middle of that decision must be the same
/// object afterwards, or its ref is disposed when the server answers.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final t0 = DateTime.utc(2026, 11, 5, 13);

  test('decisionServiceProvider survives last-contact updates', () async {
    SharedPreferences.setMockInitialValues({});
    await PairedDeviceStore().save(
      PairedDevice(
        deviceId: 'dev_0123456789',
        serverUrl: Uri.parse('https://vouch.example.com'),
        serverName: 'h',
        requireUserAuth: true,
        userAuthBound: 'attested',
        pairedAt: t0,
      ),
    );
    final keys = FakeKeys();
    await keys.generate(
      alias: DeviceKeyStore.decisionAlias,
      challenge: Uint8List(32),
      requireUserAuth: true,
    );
    final container = ProviderContainer(
      overrides: [
        deviceKeyStoreProvider.overrideWithValue(keys),
        httpClientProvider.overrideWithValue(
          () => MockClient((_) async => http.Response('', 500)),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(pairedDeviceProvider.future);

    final before = container.read(decisionServiceProvider);
    expect(before, isNotNull);

    final notifier = container.read(pairedDeviceProvider.notifier);
    await notifier.applyServer(
      lastContactAt: t0.add(const Duration(seconds: 1)),
    );
    await notifier.applyServer(
      lastContactAt: t0.add(const Duration(seconds: 2)),
    );
    expect(
      container.read(pairedDeviceProvider).value?.lastContactAt,
      t0.add(const Duration(seconds: 2)),
      reason: 'the pairing did change',
    );

    expect(container.read(decisionServiceProvider), same(before));
    // And the callback the old service holds is still safe to call.
    before!.onDecided!();

    // Unpairing does take the service away.
    await notifier.clear();
    expect(container.read(decisionServiceProvider), isNull);
  });
}
