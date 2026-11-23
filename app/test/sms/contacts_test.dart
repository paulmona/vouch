import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vouch/api/vouch_api_client.dart';
import 'package:vouch/keys/device_key.dart';
import 'package:vouch/pairing/device_session.dart';
import 'package:vouch/pairing/paired_device.dart';
import 'package:vouch/screens/sms/contacts_screen.dart';
import 'package:vouch/sms/contact_picker.dart';
import 'package:vouch/sms/contact_service.dart';
import 'package:vouch/theme/vouch_theme.dart';

import '../helpers/fake_keys.dart';

/// Permitted contacts against the contract, with the server mocked.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const sam = '+12045550150';
  final t0 = DateTime.utc(2026, 11, 15, 14);
  final device = PairedDevice(
    deviceId: 'dev_0123456789',
    serverUrl: Uri.parse('https://vouch.example.com'),
    serverName: 'home-server',
    requireUserAuth: true,
    userAuthBound: 'attested',
    pairedAt: t0,
  );

  Map<String, Object?> contact(String phone, String name, String by) => {
    'phone': phone,
    'name': name,
    'added_at': t0.toIso8601String(),
    'added_by': by,
  };

  late List<http.Request> calls;

  /// Keys for a paired phone; the decision key needs Face ID.
  Future<FakeKeys> keys({bool cancel = false}) async {
    final k = FakeKeys(cancelProof: cancel);
    await k.generate(
      alias: DeviceKeyStore.transportAlias,
      challenge: Uint8List(32),
      requireUserAuth: false,
    );
    await k.generate(
      alias: DeviceKeyStore.decisionAlias,
      challenge: Uint8List(32),
      requireUserAuth: true,
    );
    return k;
  }

  http.Client Function() server(http.Response Function(http.Request) route) =>
      () => MockClient((req) async {
        calls.add(req);
        return route(req);
      });

  setUp(() => calls = []);

  group('SmsContactService.remove', () {
    final c = SmsContact(
      phone: sam,
      name: 'Sam',
      addedAt: t0,
      addedBy: SmsContactAddedByEnum.owner,
    );

    Future<(ContactChange, FakeKeys)> remove(
      http.Response response, {
      bool cancel = false,
    }) async {
      final k = await keys(cancel: cancel);
      final s = SmsContactService(
        keys: k,
        paired: device,
        httpClient: server((_) => response),
      );
      return (await s.remove(c), k);
    }

    test('DELETE by %2B path, signed behind Face ID', () async {
      final (r, k) = await remove(http.Response('', 204));
      expect(r, isA<ContactChanged>());
      expect(calls.single.method, 'DELETE');
      expect(calls.single.url.path, '/v1/sms/contacts/%2B12045550150');
      expect(k.prompts.single.title, 'Remove Sam');
    });

    test('already gone (404) counts as removed', () async {
      final (r, _) = await remove(http.Response('{"code":"not_found"}', 404));
      expect(r, isA<ContactChanged>());
    });

    test("the server's SmsError message is shown", () async {
      final (r, _) = await remove(
        http.Response(
          jsonEncode({
            'code': 'policy_requires_user_auth',
            'message': 'This server needs Face ID for contact changes.',
          }),
          422,
        ),
      );
      expect(
        r,
        isA<ContactChangeFailed>().having(
          (f) => f.message,
          'message',
          'This server needs Face ID for contact changes.',
        ),
      );
    });

    test('cancelling Face ID sends nothing', () async {
      final (r, _) = await remove(http.Response('', 204), cancel: true);
      expect(r, isA<ContactChangeCancelled>());
      expect(calls, isEmpty);
    });
  });

  group('SmsContactService.add', () {
    Future<ContactChange> add(http.Response response) async {
      final s = SmsContactService(
        keys: await keys(),
        paired: device,
        httpClient: server((_) => response),
      );
      return s.add(name: 'Sam', phone: '(204) 555-0150');
    }

    test('POSTs the picked number as is, signed behind Face ID', () async {
      final r = await add(
        http.Response(
          jsonEncode(contact(sam, 'Sam', 'owner')),
          201,
          headers: {'content-type': 'application/json'},
        ),
      );
      expect(r, isA<ContactChanged>());
      expect(calls.single.method, 'POST');
      expect(calls.single.url.path, '/v1/sms/contacts');
      expect(jsonDecode(calls.single.body), {
        'phone': '(204) 555-0150',
        'name': 'Sam',
      });
    });

    for (final (status, code, message) in [
      (422, 'invalid_number', 'That number has too few digits.'),
      (409, 'contact_exists', 'Sam can already be texted.'),
    ]) {
      test('$code: the reason is shown', () async {
        final r = await add(
          http.Response(jsonEncode({'code': code, 'message': message}), status),
        );
        expect(
          r,
          isA<ContactChangeFailed>().having((f) => f.message, 'msg', message),
        );
      });
    }
  });

  testWidgets('add: picker, name, Face ID, list refreshes', (tester) async {
    var added = false;
    final k = await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues({});
      await PairedDeviceStore().save(device);
      return keys();
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          deviceKeyStoreProvider.overrideWithValue(k!),
          contactPickerProvider.overrideWithValue(
            _FakePicker((name: 'Sam Example', phone: '204-555-0150')),
          ),
          httpClientProvider.overrideWithValue(
            server((req) {
              if (req.method == 'POST') {
                added = true;
                return http.Response(
                  jsonEncode(contact(sam, 'Sam', 'owner')),
                  201,
                  headers: {'content-type': 'application/json'},
                );
              }
              return http.Response(
                jsonEncode({
                  'contacts': [if (added) contact(sam, 'Sam', 'owner')],
                }),
                200,
                headers: {'content-type': 'application/json'},
              );
            }),
          ),
        ],
        child: MaterialApp(
          theme: VouchTheme.light(),
          home: const ContactsScreen(),
        ),
      ),
    );
    Future<void> settle() async {
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
    }

    await settle();
    expect(find.text('Nobody yet.'), findsOneWidget);
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(find.text('204-555-0150'), findsOneWidget);
    // The name from Contacts, shortened by the owner.
    await tester.enterText(find.byType(TextField), 'Sam');
    await tester.pump();
    await tester.tap(find.textContaining('Add with'));
    await settle();

    expect(jsonDecode(calls.firstWhere((c) => c.method == 'POST').body), {
      'phone': '204-555-0150',
      'name': 'Sam',
    });
    expect(k.prompts.single.title, 'Add Sam');
    expect(find.text('Sam added'), findsOneWidget);
    expect(find.text('(204) 555-0150 · added by you'), findsOneWidget);
  });

  testWidgets('list, remove with confirmation, list refreshes', (tester) async {
    var removed = false;
    final k = await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues({});
      await PairedDeviceStore().save(device);
      return keys();
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          deviceKeyStoreProvider.overrideWithValue(k!),
          httpClientProvider.overrideWithValue(
            server((req) {
              if (req.method == 'DELETE') {
                removed = true;
                return http.Response('', 204);
              }
              return http.Response(
                jsonEncode({
                  'contacts': [
                    if (!removed) contact(sam, 'Sam', 'owner'),
                    contact('+12045550160', 'Robin', 'agent_request'),
                  ],
                }),
                200,
                headers: {'content-type': 'application/json'},
              );
            }),
          ),
        ],
        child: MaterialApp(
          theme: VouchTheme.light(),
          home: const ContactsScreen(),
        ),
      ),
    );
    Future<void> settle() async {
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
    }

    await settle();
    // Sorted by name, with where each came from.
    expect(find.text('Robin'), findsOneWidget);
    expect(find.text('(204) 555-0150 · added by you'), findsOneWidget);
    expect(find.text('(204) 555-0160 · approved request'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Robin')).dy,
      lessThan(tester.getTopLeft(find.text('Sam')).dy),
    );

    await tester.tap(find.byTooltip('Remove Sam'));
    await tester.pumpAndSettle();
    expect(find.text('Remove Sam?'), findsOneWidget);
    await tester.tap(find.textContaining('Remove with'));
    await settle();

    expect(removed, isTrue);
    expect(find.text('Sam removed'), findsOneWidget);
    expect(find.text('(204) 555-0150 · added by you'), findsNothing);
  });
}

class _FakePicker extends ContactPicker {
  _FakePicker(this.result);
  final PickedContact? result;
  @override
  Future<PickedContact?> pick() async => result;
}
