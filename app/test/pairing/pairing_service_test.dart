import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vouch/api/canonical.dart';
import 'package:vouch/api/cloudflare_access.dart';
import 'package:vouch/api/device_signer.dart';
import 'package:vouch/keys/device_key.dart';
import 'package:vouch/pairing/pair_link.dart';
import 'package:vouch/pairing/paired_device.dart';
import 'package:vouch/pairing/pairing_service.dart';

import '../helpers/fake_keys.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  final link = PairLink.parse(
    'vouch://pair?v=1&server=https%3A%2F%2Fvouch.example.com&token=TEST-SETUP-TOKEN-1234',
  )!;
  final t0 = DateTime.utc(2026, 11, 4, 22);

  http.Response ok(Map<String, Object?> body, [int status = 201]) =>
      http.Response(
        jsonEncode(body),
        status,
        headers: {'content-type': 'application/json'},
      );

  final pairedOk = ok({
    'device_id': 'dev_0123456789',
    'server_name': 'mac-dev',
    'policy': {'require_user_auth': true},
    'user_auth_bound': 'attested',
  });

  test(
    'pairs: two different keys, a valid proof, signed by the transport key',
    () async {
      final keys = FakeKeys();
      late http.Request seen;
      final service = PairingService(
        keys: keys,
        store: PairedDeviceStore(),
        pushToken: () async => 'fcm-token',
        httpClient: () => MockClient((r) async {
          seen = r;
          return pairedOk;
        }),
        now: () => t0,
      );
      final steps = <PairingStep>[];
      final d = await service.pair(
        link,
        deviceName: 'Test phone',
        onStep: steps.add,
      );

      expect(steps, [
        PairingStep.creatingKeys,
        PairingStep.confirming,
        PairingStep.registering,
        PairingStep.done,
      ]);
      expect(seen.method, 'POST');
      expect(seen.url.toString(), 'https://vouch.example.com/v1/devices/pair');
      expect(seen.headers.containsKey(Canonical.headerDevice), isFalse);

      final body = jsonDecode(seen.body) as Map<String, Object?>;
      expect(body['setup_token'], link.token);
      expect(body['push_token'], 'fcm-token');
      expect(body['name'], 'Test phone');
      expect(body['platform'], 'android');
      expect(body['public_key'], isNot(body['transport_public_key']));
      expect(body['attestation_chain'], hasLength(2));
      expect(body['transport_attestation_chain'], hasLength(2));

      // Both keys carry SHA-256 of the token as their attestation challenge.
      final expectedChallenge = PairingService.challenge(link.token);
      expect(keys.challenges[DeviceKeyStore.decisionAlias], expectedChallenge);
      expect(keys.challenges[DeviceKeyStore.transportAlias], expectedChallenge);
      expect(keys.policies[DeviceKeyStore.decisionAlias], isTrue);
      expect(keys.policies[DeviceKeyStore.transportAlias], isFalse);

      // The proof verifies against the decision key, over "vouch-pair-v1\n" + token.
      final decisionSpki = Canonical.base64UrlDecode(
        body['public_key']! as String,
      );
      expect(
        EcdsaVerifier.fromSpki(decisionSpki).verify(
          PairingService.proofMessage(link.token),
          Canonical.base64UrlDecode(body['decision_key_proof']! as String),
        ),
        isTrue,
      );
      // One fingerprint prompt, saying what it is for.
      expect(keys.prompts.single.title, 'Confirm pairing');
      expect(keys.prompts.single.subtitle, 'vouch.example.com');

      // The request itself is signed by the transport key.
      final canonical = Canonical.string(
        method: 'POST',
        target: '/v1/devices/pair',
        bodySha256: Canonical.bodySha256Hex(seen.bodyBytes),
        timestamp: seen.headers[Canonical.headerTimestamp]!,
        nonce: seen.headers[Canonical.headerNonce]!,
      );
      final transportSpki = Canonical.base64UrlDecode(
        body['transport_public_key']! as String,
      );
      expect(
        EcdsaVerifier.fromSpki(transportSpki).verify(
          Uint8List.fromList(canonical.codeUnits),
          Canonical.base64UrlDecode(seen.headers[Canonical.headerSignature]!),
        ),
        isTrue,
      );

      expect(d.deviceId, 'dev_0123456789');
      expect(d.serverName, 'mac-dev');
      expect(d.requireUserAuth, isTrue);
      expect(d.userAuthBound, 'attested');
      expect(d.pairedAt, t0);
      expect((await PairedDeviceStore().load())!.deviceId, 'dev_0123456789');
    },
  );

  test('sendAttestation false sends empty chains', () async {
    late http.Request seen;
    final service = PairingService(
      keys: FakeKeys(),
      store: PairedDeviceStore(),
      pushToken: () async => 't',
      httpClient: () => MockClient((r) async {
        seen = r;
        return pairedOk;
      }),
    );
    await service.pair(link, deviceName: 'x', sendAttestation: false);
    final body = jsonDecode(seen.body) as Map<String, Object?>;
    expect(body['attestation_chain'], isEmpty);
    // The generated model always serialises the field; empty is what matters.
    expect(body['transport_attestation_chain'] ?? const [], isEmpty);
  });

  test('a cancelled prompt sends nothing', () async {
    var calls = 0;
    final service = PairingService(
      keys: FakeKeys(cancelProof: true),
      store: PairedDeviceStore(),
      pushToken: () async => 't',
      httpClient: () => MockClient((r) async {
        calls++;
        return pairedOk;
      }),
    );
    await expectLater(
      service.pair(link, deviceName: 'x'),
      throwsA(
        isA<PairingException>().having(
          (e) => e.error,
          'error',
          PairingError.cancelled,
        ),
      ),
    );
    expect(calls, 0);
  });

  test('no fingerprint enrolled stops before any key is made', () async {
    final keys = FakeKeys(biometrics: BiometricStatus.noneEnrolled);
    final service = PairingService(
      keys: keys,
      store: PairedDeviceStore(),
      pushToken: () async => 't',
      httpClient: () => MockClient((r) async => pairedOk),
    );
    await expectLater(
      service.pair(link, deviceName: 'x'),
      throwsA(
        isA<PairingException>().having(
          (e) => e.error,
          'error',
          PairingError.biometricsUnavailable,
        ),
      ),
    );
    expect(keys.signers, isEmpty);
  });

  test('no push token stops before any key is made', () async {
    final keys = FakeKeys();
    final service = PairingService(
      keys: keys,
      store: PairedDeviceStore(),
      pushToken: () async => null,
      httpClient: () => MockClient((r) async => pairedOk),
    );
    await expectLater(
      service.pair(link, deviceName: 'x'),
      throwsA(
        isA<PairingException>().having(
          (e) => e.error,
          'error',
          PairingError.noPushToken,
        ),
      ),
    );
    expect(keys.signers, isEmpty);
  });

  group('server errors map to PairingError', () {
    for (final (status, code, expected) in [
      (401, 'invalid_setup_token', PairingError.invalidToken),
      (422, 'attestation_failed', PairingError.attestationRefused),
      (422, 'policy_requires_user_auth', PairingError.policyRequiresUserAuth),
      (401, 'clock_skew', PairingError.clockSkew),
      (401, 'bad_signature', PairingError.server),
      (500, 'weird', PairingError.server),
    ]) {
      test('$status $code', () async {
        final service = PairingService(
          keys: FakeKeys(),
          store: PairedDeviceStore(),
          pushToken: () async => 't',
          httpClient: () => MockClient(
            (r) async =>
                ok({'code': code, 'message': 'Server says no.'}, status),
          ),
        );
        await expectLater(
          service.pair(link, deviceName: 'x'),
          throwsA(
            isA<PairingException>()
                .having((e) => e.error, 'error', expected)
                .having((e) => e.message, 'message', 'Server says no.'),
          ),
        );
      });
    }

    test('connection failure', () async {
      final service = PairingService(
        keys: FakeKeys(),
        store: PairedDeviceStore(),
        pushToken: () async => 't',
        httpClient: () =>
            MockClient((r) async => throw http.ClientException('refused')),
      );
      await expectLater(
        service.pair(link, deviceName: 'x'),
        throwsA(
          isA<PairingException>().having(
            (e) => e.error,
            'error',
            PairingError.network,
          ),
        ),
      );
    });
  });

  group('push_enabled', () {
    for (final (said, expected) in [
      (false, false),
      (true, true),
      (null, true),
    ]) {
      test('server says $said', () async {
        final service = PairingService(
          keys: FakeKeys(),
          store: PairedDeviceStore(),
          pushToken: () async => 't',
          httpClient: () => MockClient(
            (r) async => ok({
              'device_id': 'dev_0123456789',
              'server_name': 'mac-dev',
              'policy': {'require_user_auth': true},
              'user_auth_bound': 'attested',
              'push_enabled': ?said,
            }),
          ),
        );
        final d = await service.pair(link, deviceName: 'x');
        expect(d.pushEnabled, expected);
        // Kept across launches; a pairing saved before the field is push.
        final back = PairedDevice.fromJson(
          jsonDecode(jsonEncode(d.toJson())) as Map<String, Object?>,
        );
        expect(back.pushEnabled, expected);
      });
    }

    test('a pairing saved by an older app means push', () {
      final j = PairedDevice(
        deviceId: 'dev_1',
        serverUrl: Uri.parse('https://h.example'),
        serverName: 'h',
        requireUserAuth: true,
        userAuthBound: 'attested',
        pairedAt: t0,
      ).toJson()..remove('push_enabled');
      expect(PairedDevice.fromJson(j).pushEnabled, isTrue);
    });
  });

  test('PairedDevice JSON round trip', () {
    final d = PairedDevice(
      deviceId: 'dev_1',
      serverUrl: Uri.parse('https://h.example'),
      serverName: 'h',
      requireUserAuth: true,
      userAuthBound: 'attested',
      pairedAt: t0,
      lastContactAt: t0.add(const Duration(minutes: 1)),
    );
    final back = PairedDevice.fromJson(
      jsonDecode(jsonEncode(d.toJson())) as Map<String, Object?>,
    );
    expect(back.deviceId, 'dev_1');
    expect(back.serverUrl, d.serverUrl);
    expect(back.lastContactAt, d.lastContactAt);
  });

  group('Local Network prompt (iOS)', () {
    PairLink at(String server) => PairLink.parse(
      'vouch://pair?v=1&server=${Uri.encodeComponent(server)}'
      '&token=TEST-SETUP-TOKEN-1234',
    )!;

    /// Fails to connect [failures] times, then pairs; or answers 409.
    Future<(Object?, int)> pairWith(
      String server, {
      int failures = 1,
      bool serverRefuses = false,
      List<Uri>? asked,
    }) async {
      var calls = 0;
      final service = PairingService(
        askLocalNetwork: (s) async => asked?.add(s),
        keys: FakeKeys(),
        store: PairedDeviceStore(),
        pushToken: () async => 't',
        retryLocalNetwork: true,
        retryEvery: Duration.zero,
        httpClient: () => MockClient((r) async {
          calls++;
          if (serverRefuses) {
            return ok({'code': 'invalid_token', 'message': 'used'}, 409);
          }
          if (calls <= failures) {
            throw const SocketException('Local network prohibited');
          }
          return pairedOk;
        }),
      );
      try {
        await service.pair(at(server), deviceName: 'x');
        return (null, calls);
      } on Object catch (e) {
        return (e, calls);
      }
    }

    test('a LAN server is retried until the prompt is answered', () async {
      final (error, calls) = await pairWith('http://10.0.0.20:8771');
      expect(error, isNull);
      expect(calls, 2);
    });

    test('gives up after a while', () async {
      final (error, calls) = await pairWith(
        'http://192.168.1.20:8771',
        failures: 99,
      );
      expect(
        error,
        isA<PairingException>().having(
          (e) => e.error,
          'error',
          PairingError.network,
        ),
      );
      expect(calls, PairingService.localNetworkRetries + 1);
    });

    test('the prompt is asked for once, before a LAN pair call', () async {
      final asked = <Uri>[];
      await pairWith('http://10.0.0.20:8771', failures: 3, asked: asked);
      expect(asked, [Uri.parse('http://10.0.0.20:8771')]);
      await pairWith('https://vouch.example.com', asked: asked);
      expect(asked, hasLength(1));
    });

    test('a public server is not retried', () async {
      final (error, calls) = await pairWith('https://vouch.example.com');
      expect(error, isA<PairingException>());
      expect(calls, 1);
    });

    test('a server answer is never retried', () async {
      final (error, calls) = await pairWith(
        'http://10.0.0.20:8771',
        serverRefuses: true,
      );
      expect(error, isA<PairingException>());
      expect(calls, 1);
    });

    test('which hosts count as local', () {
      for (final h in [
        '10.1.2.3',
        '172.16.0.1',
        '172.31.255.1',
        '192.168.1.20',
        '169.254.1.1',
        'nas.local',
        'fd00::1',
        'fe80::1',
      ]) {
        expect(PairingService.isLocalHost(h), isTrue, reason: h);
      }
      for (final h in [
        '8.8.8.8',
        '172.32.0.1',
        'vouch.example.com',
        '2001:db8::1',
      ]) {
        expect(PairingService.isLocalHost(h), isFalse, reason: h);
      }
    });
  });

  // A token saved before pairing goes only to a host confirmed on screen,
  // never to whatever host the next scanned code names.
  group('a Cloudflare Access token saved before pairing', () {
    const token = AccessToken(clientId: 'abc.access', clientSecret: 's3cret');

    Future<http.Request> pairOnce({required bool confirmed}) async {
      late http.Request seen;
      await PairingService(
        keys: FakeKeys(),
        store: PairedDeviceStore(),
        pushToken: () async => 'fcm-token',
        httpClient: () => MockClient((r) async {
          seen = r;
          return pairedOk;
        }),
        now: () => t0,
      ).pair(link, deviceName: 'Test phone', sendPendingAccessToken: confirmed);
      return seen;
    }

    setUp(() async {
      final store = CloudflareAccessStore.instance;
      await store.remove(link.server);
      await store.save(null, token);
    });

    test('is not sent to a host nobody confirmed', () async {
      final seen = await pairOnce(confirmed: false);
      expect(seen.headers[CloudflareAccessClient.headerId], isNull);
      expect(seen.headers[CloudflareAccessClient.headerSecret], isNull);
      // Still waiting, not tied to the link's host.
      expect(await CloudflareAccessStore.instance.read(link.server), isNull);
      expect(
        (await CloudflareAccessStore.instance.read(null))?.clientId,
        'abc.access',
      );
    });

    test('goes to the host confirmed on screen', () async {
      final seen = await pairOnce(confirmed: true);
      expect(seen.headers[CloudflareAccessClient.headerId], 'abc.access');
      expect(await CloudflareAccessStore.instance.read(null), isNull);
    });
  });
}
