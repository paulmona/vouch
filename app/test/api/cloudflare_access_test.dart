import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vouch/api/cloudflare_access.dart';
import 'package:vouch/api/device_signer.dart';
import 'package:vouch/api/vouch_api_client.dart';
import 'package:vouch/screens/cloudflare_access_screen.dart';

import '../helpers/memory_secrets.dart';

/// Cloudflare Access, with Cloudflare mocked: no live Access setup.
void main() {
  final server = Uri.parse('https://vouch.example.com');
  const token = AccessToken(clientId: 'abc.access', clientSecret: 's3cret');

  late MemorySecrets secrets;
  late CloudflareAccessStore store;
  late List<http.BaseRequest> sent;

  setUp(() {
    secrets = MemorySecrets();
    store = CloudflareAccessStore(backend: secrets);
    sent = [];
  });

  http.Client ok() => MockClient((req) async {
    sent.add(req);
    return http.Response(
      '{}',
      200,
      headers: {'content-type': 'application/json'},
    );
  });

  CloudflareAccessClient client(http.Client inner) =>
      CloudflareAccessClient(inner: inner, server: server, store: store);

  group('headers', () {
    test('sent to the paired origin when a token is set', () async {
      await store.save(server, token);
      await client(ok()).get(server.resolve('/v1/devices/me'));
      expect(sent.single.headers['CF-Access-Client-Id'], 'abc.access');
      expect(sent.single.headers['CF-Access-Client-Secret'], 's3cret');
    });

    test('never sent to another host, port or scheme', () async {
      await store.save(server, token);
      final c = client(ok());
      for (final other in [
        'https://evil.example.com/v1/devices/me',
        'https://vouch.example.com:8443/v1/devices/me',
        'http://vouch.example.com/v1/devices/me',
      ]) {
        await c.get(Uri.parse(other));
      }
      for (final r in sent) {
        expect(r.headers.keys, isNot(contains('CF-Access-Client-Id')));
        expect(r.headers.keys, isNot(contains('CF-Access-Client-Secret')));
      }
    });

    test('never sent over plain HTTP, even to the paired server', () async {
      final lan = Uri.parse('http://192.168.1.20:8771');
      await store.save(lan, token);
      await CloudflareAccessClient(
        inner: ok(),
        server: lan,
        store: store,
      ).get(lan.resolve('/v1/devices/me'));
      expect(sent.single.headers.keys, isNot(contains('CF-Access-Client-Id')));
      expect(
        sent.single.headers.keys,
        isNot(contains('CF-Access-Client-Secret')),
      );
    });

    test('not sent when no token is set', () async {
      await client(ok()).get(server.resolve('/v1/devices/me'));
      expect(sent.single.headers.keys, isNot(contains('CF-Access-Client-Id')));
    });

    test('redirects are never followed', () async {
      await client(ok()).get(server.resolve('/v1/devices/me'));
      expect(sent.single.followRedirects, isFalse);
    });

    // No device id, as while pairing.
    test('through VouchApi, signed as before, pairing included', () async {
      await store.save(server, token);
      final api = VouchApi(
        serverUrl: server,
        signer: SoftwareSigner.generate(),
        inner: ok(),
        accessStore: store,
      );
      // The stub's `{}` isn't a Device; only the request matters here.
      await expectLater(api.devices.getDevice(), throwsA(anything));
      final r = sent.single;
      expect(r.headers['CF-Access-Client-Id'], 'abc.access');
      expect(r.headers['X-Vouch-Signature'], isNotNull);
    });
  });

  group('blocked', () {
    Future<Object?> errorFrom(http.Response response) async {
      final c = client(MockClient((_) async => response));
      try {
        await c.get(server.resolve('/v1/devices/me'));
        return null;
      } on Object catch (e) {
        return e;
      }
    }

    test('an HTML page is an Access block', () async {
      final e = await errorFrom(
        http.Response(
          '<html>Sign in</html>',
          200,
          headers: {'content-type': 'text/html; charset=utf-8'},
        ),
      );
      expect(isAccessBlocked(e), isTrue);
      expect((e! as http.ClientException).message, accessBlockedMessage);
    });

    test('a redirect to *.cloudflareaccess.com is an Access block', () async {
      final e = await errorFrom(
        http.Response(
          '',
          302,
          headers: {
            'location':
                'https://myteam.cloudflareaccess.com/cdn-cgi/access/login',
          },
        ),
      );
      expect(isAccessBlocked(e), isTrue);
    });

    test('a JSON error is not', () async {
      final e = await errorFrom(
        http.Response(
          jsonEncode({'code': 'not_found'}),
          404,
          headers: {'content-type': 'application/json'},
        ),
      );
      expect(e, isNull);
    });

    test('the generated client wraps it, still recognised', () async {
      final api = VouchApi(
        serverUrl: server,
        signer: SoftwareSigner.generate(),
        inner: MockClient(
          (_) async => http.Response(
            '<html></html>',
            403,
            headers: {'content-type': 'text/html'},
          ),
        ),
        accessStore: store,
      );
      Object? error;
      try {
        await api.devices.getDevice();
      } on Object catch (e) {
        error = e;
      }
      expect(error, isA<ApiException>());
      expect(isAccessBlocked(error), isTrue);
    });
  });

  group('store', () {
    test('Remove clears the stored token', () async {
      await store.save(server, token);
      await store.remove(server);
      expect(await store.read(server), isNull);
      expect(secrets.values, isEmpty);
      // A fresh store (next launch) finds nothing either.
      expect(
        await CloudflareAccessStore(backend: secrets).read(server),
        isNull,
      );
    });

    test('a token saved before pairing moves to the paired server', () async {
      await store.save(null, token);
      await store.bindPending(server);
      expect((await store.read(server))?.clientId, 'abc.access');
      expect(await store.read(null), isNull);
    });

    test('a pending token is not tied to a plain HTTP server', () async {
      await store.save(null, token);
      final lan = Uri.parse('http://192.168.1.20:8771');
      await store.bindPending(lan);
      expect(await store.read(lan), isNull);
      expect((await store.read(null))?.clientId, 'abc.access');
    });
  });

  group('screen', () {
    Future<void> open(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ScaffoldMessenger(
            child: CloudflareAccessScreen(server: server, store: store),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('save, the secret is not shown again, then remove', (
      tester,
    ) async {
      await open(tester);
      expect(find.text('Service token set'), findsNothing);
      await tester.enterText(
        find.widgetWithText(TextField, 'Client ID'),
        ' abc.access ',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Client Secret'),
        's3cret',
      );
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('Service token set'), findsOneWidget);
      expect(find.text('Client ID abc.access'), findsOneWidget);
      expect(find.text('s3cret'), findsNothing);
      expect((await store.read(server))?.clientSecret, 's3cret');

      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      expect(find.text('Service token set'), findsNothing);
      expect(await store.read(server), isNull);
    });
  });
}
