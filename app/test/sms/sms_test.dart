import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vouch/app.dart';
import 'package:vouch/keys/device_key.dart';
import 'package:vouch/pairing/device_session.dart';
import 'package:vouch/pairing/paired_device.dart';
import 'package:vouch/push/push_event.dart';
import 'package:vouch/screens/sms/messages_tab.dart';
import 'package:vouch/screens/sms/thread_screen.dart';
import 'package:vouch/server/modules.dart';
import 'package:vouch/sms/phone_format.dart';
import 'package:vouch/sms/sms_providers.dart';
import 'package:vouch/theme/vouch_theme.dart';

import '../helpers/fake_keys.dart';

/// Messages against the contract, with the server mocked.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const sam = '+12045550150';
  final t0 = DateTime.utc(2026, 11, 15, 14);

  Map<String, Object?> msg(
    String id,
    int minutes, {
    bool out = false,
    String status = 'received',
    String phone = sam,
  }) => {
    'message_id': id,
    'phone': phone,
    'direction': out ? 'outbound' : 'inbound',
    'text': 'text $id',
    'at': t0.add(Duration(minutes: minutes)).toIso8601String(),
    'status': out && status == 'received' ? 'sent' : status,
  };

  late List<http.Request> calls;

  /// A paired phone; [route] answers each request by its path and query.
  Future<List<Override>> paired(
    Object? Function(http.Request req) route,
  ) async {
    calls = [];
    SharedPreferences.setMockInitialValues({});
    await PairedDeviceStore().save(
      PairedDevice(
        deviceId: 'dev_0123456789',
        serverUrl: Uri.parse('https://vouch.example.com'),
        serverName: 'home-server',
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
    return [
      deviceKeyStoreProvider.overrideWithValue(keys),
      httpClientProvider.overrideWithValue(
        () => MockClient((req) async {
          calls.add(req);
          final body = route(req);
          if (body is int) return http.Response('{"code":"not_found"}', body);
          if (body == null) return http.Response('', 500);
          return http.Response(
            jsonEncode(body),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      ),
    ];
  }

  test('sms_updated parses with no id', () {
    expect(
      PushEvent.parse({'v': '1', 'kind': 'sms_updated'}),
      isA<SmsUpdatedPush>(),
    );
  });

  test('phone formatting', () {
    expect(formatPhone(sam), '(204) 555-0150');
    expect(formatPhone('+447700900123'), '+447700900123');
  });

  group('thread paging', () {
    Future<ProviderContainer> container(List<Override> o) async {
      final c = ProviderContainer(overrides: o);
      addTearDown(c.dispose);
      await c.read(pairedDeviceProvider.future);
      return c;
    }

    test(
      'first page by %2B path, then older pages with before=, then stop',
      () async {
        final c = await container(
          await paired((req) {
            if (req.url.path !=
                '/v1/sms/conversations/%2B12045550150/messages') {
              return null;
            }
            return switch (req.url.queryParameters['before']) {
              null => {
                'messages': [msg('m3m3m3m3', 3), msg('m2m2m2m2', 2)],
                'next_before': 'm2m2m2m2',
              },
              'm2m2m2m2' => {
                'messages': [msg('m1m1m1m1', 1)],
                'next_before': null,
              },
              _ => null,
            };
          }),
        );
        final sub = c.listen(smsThreadProvider(sam), (_, _) {});
        addTearDown(sub.close);
        var s = await c.read(smsThreadProvider(sam).future);
        expect(s.messages.map((m) => m.messageId), ['m3m3m3m3', 'm2m2m2m2']);
        expect(s.hasOlder, isTrue);
        // The signed target keeps the encoded +.
        expect(
          calls.first.url.toString(),
          contains('/v1/sms/conversations/%2B12045550150/messages'),
        );

        await c.read(smsThreadProvider(sam).notifier).loadOlder();
        s = c.read(smsThreadProvider(sam)).requireValue;
        expect(s.messages.map((m) => m.messageId), [
          'm3m3m3m3',
          'm2m2m2m2',
          'm1m1m1m1',
        ]);
        expect(s.hasOlder, isFalse);

        final before = calls.length;
        await c.read(smsThreadProvider(sam).notifier).loadOlder();
        expect(calls.length, before, reason: 'no older page to fetch');
      },
    );

    test(
      'a refresh (sms_updated) adds the new message, keeps older pages',
      () async {
        var round = 0;
        final c = await container(
          await paired((req) {
            if (!req.url.path.endsWith('/messages')) return null;
            final before = req.url.queryParameters['before'];
            if (before == 'm2m2m2m2') {
              return {
                'messages': [msg('m1m1m1m1', 1)],
                'next_before': null,
              };
            }
            return round == 0
                ? {
                    'messages': [msg('m3m3m3m3', 3), msg('m2m2m2m2', 2)],
                    'next_before': 'm2m2m2m2',
                  }
                : {
                    'messages': [
                      msg('m4m4m4m4', 4, out: true),
                      msg('m3m3m3m3', 3),
                    ],
                    'next_before': 'm3m3m3m3',
                  };
          }),
        );
        final sub = c.listen(smsThreadProvider(sam), (_, _) {});
        addTearDown(sub.close);
        await c.read(smsThreadProvider(sam).future);
        await c.read(smsThreadProvider(sam).notifier).loadOlder();

        round = 1;
        c.invalidate(smsThreadProvider);
        final s = await c.read(smsThreadProvider(sam).future);
        expect(s.messages.map((m) => m.messageId), [
          'm4m4m4m4',
          'm3m3m3m3',
          'm2m2m2m2',
          'm1m1m1m1',
        ]);
        expect(s.hasOlder, isFalse);
      },
    );
  });

  group('screens', () {
    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
    }

    testWidgets('conversation list: names, numbers, unread, agent prefix', (
      tester,
    ) async {
      final overrides = await tester.runAsync(
        () => paired(
          (req) => req.url.path == '/v1/sms/conversations'
              ? {
                  'conversations': [
                    {
                      'phone': sam,
                      'contact_name': 'Sam',
                      'last_message': msg('m9m9m9m9', 9, out: true),
                      'unread_count': 0,
                    },
                    {
                      'phone': '+12045550160',
                      'contact_name': null,
                      'last_message': msg('n1n1n1n1', 5, phone: '+12045550160'),
                      'unread_count': 2,
                    },
                  ],
                }
              : null,
        ),
      );
      final device = await tester.runAsync(() => PairedDeviceStore().load());
      await tester.pumpWidget(
        ProviderScope(
          overrides: overrides!,
          child: MaterialApp(
            theme: VouchTheme.light(),
            home: Scaffold(body: MessagesTab(device: device!)),
          ),
        ),
      );
      await settle(tester);

      expect(find.text('Sam'), findsOneWidget);
      expect(find.text('Agent: text m9m9m9m9'), findsOneWidget);
      expect(find.text('(204) 555-0160'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('a 404 on the list rechecks modules, says nothing about off', (
      tester,
    ) async {
      final overrides = await tester.runAsync(() => paired((_) => 404));
      final device = await tester.runAsync(() => PairedDeviceStore().load());
      await tester.pumpWidget(
        ProviderScope(
          overrides: overrides!,
          child: MaterialApp(
            // Home watches the modules, as here.
            home: Consumer(
              builder: (context, ref, _) {
                ref.watch(modulesProvider);
                return Scaffold(body: MessagesTab(device: device!));
              },
            ),
          ),
        ),
      );
      await settle(tester);
      expect(find.text("Couldn't load messages"), findsOneWidget);
      // Once on start, once more after the list's 404.
      expect(calls.where((c) => c.url.path == '/v1/server/modules').length, 2);
    });

    testWidgets('a 404 on a thread means it was deleted', (tester) async {
      final overrides = await tester.runAsync(
        () => paired((req) => req.url.path.endsWith('/messages') ? 404 : null),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: overrides!,
          child: const MaterialApp(home: ThreadScreen(phone: sam)),
        ),
      );
      await settle(tester);
      expect(find.text('This conversation has been deleted.'), findsOneWidget);
    });

    testWidgets('thread: bubbles, day label, failed send, by name', (
      tester,
    ) async {
      final overrides = await tester.runAsync(
        () => paired(
          (req) => req.url.path.endsWith('/messages')
              ? {
                  'messages': [
                    msg('m3m3m3m3', 3, out: true, status: 'failed'),
                    msg('m2m2m2m2', 2, out: true),
                    msg('m1m1m1m1', 1),
                  ],
                  'next_before': null,
                }
              : {'conversations': <Object>[]},
        ),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: overrides!,
          child: MaterialApp(
            theme: VouchTheme.light(),
            home: const ThreadScreen(phone: sam, name: 'Sam'),
          ),
        ),
      );
      await settle(tester);

      expect(find.text('Sam'), findsOneWidget);
      expect(find.text('(204) 555-0150'), findsOneWidget);
      expect(find.text('text m1m1m1m1'), findsOneWidget);
      expect(find.textContaining('Not delivered'), findsOneWidget);
      expect(find.textContaining('Nov 2026'), findsOneWidget);
    });

    testWidgets('the thread route carries a + through go_router', (
      tester,
    ) async {
      final overrides = await tester.runAsync(
        () => paired(
          (req) => req.url.path.endsWith('/messages')
              ? {'messages': <Object>[], 'next_before': null}
              : null,
        ),
      );
      final router = buildRouter();
      await tester.pumpWidget(
        ProviderScope(
          overrides: overrides!,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      router.go(Routes.smsThread(sam, name: 'Sam & Co'));
      await settle(tester);
      final screen = tester.widget<ThreadScreen>(find.byType(ThreadScreen));
      expect(screen.phone, sam);
      expect(screen.name, 'Sam & Co');
    });
  });
}
