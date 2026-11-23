import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vouch/api/canonical.dart';
import 'package:vouch/api/device_signer.dart';
import 'package:vouch/keys/device_key.dart';
import 'package:vouch/pairing/device_session.dart';
import 'package:vouch/pairing/paired_device.dart';

import '../helpers/fake_keys.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final t0 = DateTime.utc(2026, 11, 4, 22);

  Future<(ProviderContainer, FakeKeys)> setUpPaired(
    Future<http.Response> Function(http.Request) handler,
  ) async {
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
      alias: DeviceKeyStore.transportAlias,
      challenge: Uint8List(32),
      requireUserAuth: false,
    );
    final container = ProviderContainer(
      overrides: [
        deviceKeyStoreProvider.overrideWithValue(keys),
        httpClientProvider.overrideWithValue(() => MockClient(handler)),
      ],
    );
    addTearDown(container.dispose);
    // Load the pairing before anything watches the API.
    await container.read(pairedDeviceProvider.future);
    return (container, keys);
  }

  test(
    'GET /v1/devices/me is signed by the transport key with the device id',
    () async {
      late http.Request seen;
      final (c, keys) = await setUpPaired((r) async {
        seen = r;
        return http.Response(
          jsonEncode({
            'device_id': 'dev_0123456789',
            'name': 'Test phone',
            'platform': 'android',
            'paired_at': '2026-11-04T22:00:00Z',
            'last_checkin_at': null,
            'user_auth_bound': 'attested',
            'policy': {'require_user_auth': false},
            'rekey_required': true,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final status = await c.read(deviceStatusProvider.future);
      expect(status, isA<DeviceOnline>());
      expect(seen.method, 'GET');
      expect(seen.url.toString(), 'https://vouch.example.com/v1/devices/me');
      expect(seen.headers[Canonical.headerDevice], 'dev_0123456789');
      final canonical = Canonical.string(
        method: 'GET',
        target: '/v1/devices/me',
        bodySha256: Canonical.bodySha256Hex(const []),
        timestamp: seen.headers[Canonical.headerTimestamp]!,
        nonce: seen.headers[Canonical.headerNonce]!,
      );
      final spki = await keys.publicKeySpki(DeviceKeyStore.transportAlias);
      expect(
        EcdsaVerifier.fromSpki(spki).verify(
          Uint8List.fromList(canonical.codeUnits),
          Canonical.base64UrlDecode(seen.headers[Canonical.headerSignature]!),
        ),
        isTrue,
      );
      // No prompt: the transport key needs none.
      expect(keys.prompts, isEmpty);

      // The pairing picked up the server's policy and the rekey flag.
      final paired = c.read(pairedDeviceProvider).value!;
      expect(paired.requireUserAuth, isFalse);
      expect(paired.rekeyRequired, isTrue);
      expect(paired.lastContactAt, isNotNull);
    },
  );

  test(
    'updating last contact does not rebuild the API (no refresh loop)',
    () async {
      var calls = 0;
      final (c, _) = await setUpPaired((r) async {
        calls++;
        return http.Response(
          jsonEncode({
            'device_id': 'dev_0123456789',
            'name': 'Test phone',
            'platform': 'android',
            'paired_at': '2026-11-04T22:00:00Z',
            'user_auth_bound': 'attested',
            'policy': {'require_user_auth': true},
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final apiBefore = c.read(transportApiProvider);
      final sub = c.listen(deviceStatusProvider, (_, _) {});
      addTearDown(sub.close);
      await c.read(deviceStatusProvider.future);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(identical(c.read(transportApiProvider), apiBefore), isTrue);
      expect(calls, 1);
    },
  );

  test('401 means the server no longer knows this device', () async {
    final (c, _) = await setUpPaired(
      (r) async =>
          http.Response('{"code":"unknown_device","message":"x"}', 401),
    );
    expect(await c.read(deviceStatusProvider.future), isA<DeviceUnpaired>());
    expect(c.read(pairedDeviceProvider).value!.lastContactAt, isNull);
  });

  test('a connection failure is reported, not thrown', () async {
    final (c, _) = await setUpPaired(
      (r) async => throw http.ClientException('refused'),
    );
    expect(await c.read(deviceStatusProvider.future), isA<DeviceUnreachable>());
  });

  test('not paired: no API, no status', () async {
    SharedPreferences.setMockInitialValues({});
    final c = ProviderContainer(
      overrides: [deviceKeyStoreProvider.overrideWithValue(FakeKeys())],
    );
    addTearDown(c.dispose);
    await c.read(pairedDeviceProvider.future);
    expect(c.read(transportApiProvider), isNull);
    expect(await c.read(deviceStatusProvider.future), isNull);
  });
}
