import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vouch/api/canonical.dart';
import 'package:vouch/keys/device_key.dart';
import 'package:vouch/pairing/device_session.dart';
import 'package:vouch/pairing/paired_device.dart';
import 'package:vouch/push/push_token_sync.dart';

import '../helpers/fake_keys.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<ProviderContainer> paired(
    Future<http.Response> Function(http.Request) handler, {
    bool isPaired = true,
  }) async {
    SharedPreferences.setMockInitialValues({});
    if (isPaired) {
      await PairedDeviceStore().save(
        PairedDevice(
          deviceId: 'dev_0123456789',
          serverUrl: Uri.parse('https://vouch.example.com'),
          serverName: 'h',
          requireUserAuth: true,
          userAuthBound: 'attested',
          pairedAt: DateTime.utc(2026, 11, 4),
        ),
      );
    }
    final keys = FakeKeys();
    await keys.generate(
      alias: DeviceKeyStore.transportAlias,
      challenge: Uint8List(32),
      requireUserAuth: false,
    );
    final c = ProviderContainer(
      overrides: [
        deviceKeyStoreProvider.overrideWithValue(keys),
        httpClientProvider.overrideWithValue(() => MockClient(handler)),
      ],
    );
    addTearDown(c.dispose);
    await c.read(pairedDeviceProvider.future);
    return c;
  }

  test(
    'a rotated token is PUT to the server, signed, once per value',
    () async {
      final seen = <http.Request>[];
      final c = await paired((r) async {
        seen.add(r);
        return http.Response('', 204);
      });
      final tokens = StreamController<String>();
      final sync = PushTokenSync(c.read(_refProvider), tokens: tokens.stream)
        ..start();
      addTearDown(sync.stop);

      tokens.add('tok-1');
      tokens.add('tok-1');
      tokens.add('tok-2');
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(seen.map((r) => r.method), ['PUT', 'PUT']);
      expect(seen.first.url.path, '/v1/devices/me/push-token');
      expect(jsonDecode(seen.first.body), {'push_token': 'tok-1'});
      expect(jsonDecode(seen.last.body), {'push_token': 'tok-2'});
      expect(seen.first.headers[Canonical.headerDevice], 'dev_0123456789');
      expect(seen.first.headers[Canonical.headerSignature], isNotEmpty);
    },
  );

  test('a token already held when sync starts is sent too', () async {
    final seen = <http.Request>[];
    final c = await paired((r) async {
      seen.add(r);
      return http.Response('', 204);
    });
    final sync = PushTokenSync(
      c.read(_refProvider),
      tokens: const Stream.empty(),
      current: () => 'early-token',
    )..start();
    addTearDown(sync.stop);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(seen, hasLength(1));
    expect(jsonDecode(seen.single.body), {'push_token': 'early-token'});
  });

  test('not paired: nothing is sent', () async {
    var calls = 0;
    final c = await paired((r) async {
      calls++;
      return http.Response('', 204);
    }, isPaired: false);
    final sync = PushTokenSync(
      c.read(_refProvider),
      tokens: Stream.value('tok'),
    )..start();
    addTearDown(sync.stop);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(calls, 0);
    expect(await sync.send('tok'), isFalse);
  });

  test('a refused update is reported, not thrown', () async {
    final c = await paired(
      (r) async => http.Response('{"code":"unknown_device"}', 401),
    );
    final sync = PushTokenSync(
      c.read(_refProvider),
      tokens: const Stream.empty(),
    );
    expect(await sync.send('tok'), isFalse);
  });
}

/// Hands a [Ref] to the test.
final _refProvider = Provider<Ref>((ref) => ref);
