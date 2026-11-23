import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vouch/api/vouch_api_client.dart' show Modules;
import 'package:vouch/dev/sample_requests.dart';
import 'package:vouch/keys/device_key.dart';
import 'package:vouch/pairing/device_session.dart';
import 'package:vouch/pairing/paired_device.dart';
import 'package:vouch/screens/home_screen.dart';
import 'package:vouch/server/modules.dart';
import 'package:vouch/theme/vouch_theme.dart';

import 'helpers/fake_keys.dart';

/// The app shows only what the server's module switches allow.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// A paired phone whose server answers /v1/server/modules with
  /// [modules] (a status code, or a JSON body).
  Future<List<Override>> paired({
    required Object modules,
    List<Map<String, Object?>> pending = const [],
  }) async {
    SharedPreferences.setMockInitialValues({});
    await PairedDeviceStore().save(
      PairedDevice(
        deviceId: 'dev_0123456789',
        serverUrl: Uri.parse('https://vouch.example.com'),
        serverName: 'home-server',
        requireUserAuth: true,
        userAuthBound: 'attested',
        pairedAt: DateTime.utc(2026, 11, 15),
      ),
    );
    final keys = FakeKeys();
    await keys.generate(
      alias: DeviceKeyStore.transportAlias,
      challenge: Uint8List(32),
      requireUserAuth: false,
    );
    http.Response json(Object body) => http.Response(
      jsonEncode(body),
      200,
      headers: {'content-type': 'application/json'},
    );
    return [
      deviceKeyStoreProvider.overrideWithValue(keys),
      httpClientProvider.overrideWithValue(
        () => MockClient((req) async {
          switch (req.url.path) {
            case '/v1/server/modules':
              return modules is int
                  ? http.Response('{"code":"x","message":"x"}', modules)
                  : json(modules);
            case '/v1/requests/pending':
              return json({'requests': pending});
            case '/v1/sms/conversations':
              return json({'conversations': <Object>[]});
          }
          return http.Response('', 500);
        }),
      ),
    ];
  }

  group('modulesProvider', () {
    Future<Modules> read(List<Override> overrides) async {
      final c = ProviderContainer(overrides: overrides);
      addTearDown(c.dispose);
      await c.read(pairedDeviceProvider.future);
      return c.read(modulesProvider.future);
    }

    test('reads the server switches', () async {
      final m = await read(
        await paired(modules: {'credentials': false, 'sms': true}),
      );
      expect((m.credentials, m.sms), (false, true));
    });

    test('a server without the endpoint (404) is credentials only', () async {
      final m = await read(await paired(modules: 404));
      expect((m.credentials, m.sms), (true, false));
    });

    test('a failure keeps the last answer', () async {
      final ok = await paired(modules: {'credentials': true, 'sms': true});
      await read(ok);
      // Same prefs (the cache), server now failing.
      final c = ProviderContainer(
        overrides: [
          ok.first,
          httpClientProvider.overrideWithValue(
            () => MockClient((_) async => http.Response('', 503)),
          ),
        ],
      );
      addTearDown(c.dispose);
      await c.read(pairedDeviceProvider.future);
      final m = await c.read(modulesProvider.future);
      expect((m.credentials, m.sms), (true, true));
    });
  });

  group('Home follows the switches', () {
    final signIn = SampleRequests.signIn(
      remaining: const Duration(hours: 1),
    ).toJson();

    Future<void> pumpHome(
      WidgetTester tester, {
      required bool credentials,
      required bool sms,
    }) async {
      final overrides = await tester.runAsync(
        () => paired(
          modules: {'credentials': credentials, 'sms': sms},
          pending: [jsonDecode(jsonEncode(signIn)) as Map<String, Object?>],
        ),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: overrides!,
          child: MaterialApp(
            theme: VouchTheme.light(),
            home: const HomeScreen(),
          ),
        ),
      );
      // Real prefs and HTTP futures: let them finish outside fake time.
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
    }

    for (final (credentials, sms) in [
      (true, true),
      (true, false),
      (false, true),
      (false, false),
    ]) {
      testWidgets('credentials=$credentials sms=$sms', (tester) async {
        await pumpHome(tester, credentials: credentials, sms: sms);

        expect(find.byType(NavigationBar), sms ? findsOneWidget : findsNothing);
        expect(find.text('Messages'), sms ? findsOneWidget : findsNothing);
        // The sample sign-in request is listed only with credentials on.
        expect(
          find.textContaining('Scout'),
          credentials ? findsOneWidget : findsNothing,
        );

        if (sms) {
          await tester.tap(find.text('Messages'));
          for (var i = 0; i < 5; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 20)),
            );
            await tester.pump();
          }
          expect(find.text('No messages yet'), findsOneWidget);
          expect(find.text('Pending requests'), findsNothing);
        }
      });
    }
  });
}
