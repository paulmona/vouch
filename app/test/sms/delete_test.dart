import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vouch/keys/device_key.dart';
import 'package:vouch/pairing/device_session.dart';
import 'package:vouch/pairing/paired_device.dart';
import 'package:vouch/screens/sms/thread_screen.dart';
import 'package:vouch/theme/vouch_theme.dart';

import '../helpers/fake_keys.dart';

/// Delete selected messages, or the whole conversation, from Vouch.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const sam = '+12045550150';
  final t0 = DateTime.utc(2026, 11, 15, 14);

  Map<String, Object?> msg(String id, int minutes) => {
    'message_id': id,
    'phone': sam,
    'direction': 'inbound',
    'text': 'text $id',
    'at': t0.add(Duration(minutes: minutes)).toIso8601String(),
    'status': 'received',
  };

  late List<http.Request> calls;

  /// The thread screen, opened from a list so it can pop back. [route]
  /// answers each request; the thread holds three messages.
  Future<void> open(
    WidgetTester tester, {
    http.Response Function(http.Request)? onDelete,
  }) async {
    calls = [];
    final keys = await tester.runAsync(() async {
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
      final k = FakeKeys();
      await k.generate(
        alias: DeviceKeyStore.transportAlias,
        challenge: Uint8List(32),
        requireUserAuth: false,
      );
      return k;
    });
    http.Response json(Object body) => http.Response(
      jsonEncode(body),
      200,
      headers: {'content-type': 'application/json'},
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          deviceKeyStoreProvider.overrideWithValue(keys!),
          httpClientProvider.overrideWithValue(
            () => MockClient((req) async {
              calls.add(req);
              if (req.method == 'GET' && req.url.path.endsWith('/messages')) {
                return json({
                  'messages': [
                    msg('m3m3m3m3', 3),
                    msg('m2m2m2m2', 2),
                    msg('m1m1m1m1', 1),
                  ],
                  'next_before': null,
                });
              }
              if (req.method == 'GET') {
                return json({'conversations': <Object>[]});
              }
              return onDelete?.call(req) ?? json({'deleted': 2});
            }),
          ),
        ],
        child: MaterialApp(
          theme: VouchTheme.light(),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const ThreadScreen(phone: sam, name: 'Sam'),
                  ),
                ),
                child: const Text('List'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('List'));
    await settle(tester);
  }

  testWidgets('select two, delete: server gets those ids, they vanish', (
    tester,
  ) async {
    await open(tester);
    await tester.longPress(find.text('text m1m1m1m1'));
    await tester.pump();
    await tester.tap(find.text('text m3m3m3m3'));
    await tester.pump();
    expect(find.text('2 selected'), findsOneWidget);

    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Delete 2 messages?'), findsOneWidget);
    expect(find.text(providerKeepsCopy), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await settle(tester);

    final post = calls.singleWhere((c) => c.method == 'POST');
    expect(post.url.path, '/v1/sms/messages/delete');
    expect((jsonDecode(post.body)['message_ids'] as List).toSet(), {
      'm1m1m1m1',
      'm3m3m3m3',
    });
    expect(find.text('text m1m1m1m1'), findsNothing);
    expect(find.text('text m3m3m3m3'), findsNothing);
    expect(find.text('text m2m2m2m2'), findsOneWidget);
    expect(find.text('2 messages deleted'), findsOneWidget);
    expect(find.text('Sam'), findsOneWidget, reason: 'selection ended');
  });

  testWidgets('a failed delete keeps the messages and the selection', (
    tester,
  ) async {
    await open(tester, onDelete: (_) => http.Response('', 500));
    await tester.longPress(find.text('text m2m2m2m2'));
    await tester.pump();
    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await settle(tester);

    expect(find.text('text m2m2m2m2'), findsOneWidget);
    expect(find.text('1 selected'), findsOneWidget);
    expect(find.textContaining('refused to delete'), findsOneWidget);
  });

  testWidgets('copy one message', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    await open(tester);
    await tester.longPress(find.text('text m2m2m2m2'));
    await tester.pump();
    await tester.tap(find.byTooltip('Copy'));
    await tester.pump();
    expect(copied, 'text m2m2m2m2');
  });

  testWidgets('delete the conversation: DELETE by %2B, back to the list', (
    tester,
  ) async {
    await open(tester, onDelete: (_) => http.Response('', 204));
    await tester.tap(find.byType(PopupMenuButton<void>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete conversation'));
    await tester.pumpAndSettle();
    expect(find.text('Delete every message with Sam?'), findsOneWidget);
    await tester.tap(find.text('Delete all'));
    await settle(tester);

    final del = calls.singleWhere((c) => c.method == 'DELETE');
    expect(del.url.path, '/v1/sms/conversations/%2B12045550150');
    expect(find.byType(ThreadScreen), findsNothing);
    expect(find.text('Conversation deleted'), findsOneWidget);
  });
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}
