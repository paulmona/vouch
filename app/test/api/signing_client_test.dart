import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vouch/api/canonical.dart';
import 'package:vouch/api/device_signer.dart';
import 'package:vouch/api/signing_client.dart';
import 'package:vouch/api/vouch_api_client.dart';

import 'test_vectors.dart';

void main() {
  final vectors = TestVectors.load();
  final signer = SoftwareSigner.fromPkcs8Pem(vectors.privateKeyPkcs8Pem);
  final verifier = EcdsaVerifier.fromSpki(
    Canonical.base64UrlDecode(vectors.publicKeySpkiB64url),
  );

  /// Rebuilds the canonical string from what the server would see and checks
  /// the signature header against it: what the server's middleware does.
  bool serverWouldAccept(http.Request r) {
    final canonical = Canonical.string(
      method: r.method,
      target: Canonical.target(r.url),
      bodySha256: Canonical.bodySha256Hex(r.bodyBytes),
      timestamp: r.headers[Canonical.headerTimestamp]!,
      nonce: r.headers[Canonical.headerNonce]!,
    );
    return verifier.verify(
      Uint8List.fromList(canonical.codeUnits),
      Canonical.base64UrlDecode(r.headers[Canonical.headerSignature]!),
    );
  }

  group('SigningClient', () {
    for (final c in vectors.cases) {
      test('reproduces the vector "${c.name}" headers', () async {
        late http.Request seen;
        final client = SigningClient(
          signer: signer,
          inner: MockClient((req) async {
            seen = req;
            return http.Response('{}', 200);
          }),
          deviceId: c.target == '/v1/devices/pair' ? null : 'dev_123',
          clock: () => DateTime.fromMillisecondsSinceEpoch(
            int.parse(c.timestamp) * 1000,
            isUtc: true,
          ),
          nonceSource: () => c.nonce,
        );
        final req = http.Request(
          c.method,
          Uri.parse('https://vouch.example${c.target}'),
        )..bodyBytes = utf8.encode(c.body);
        await client.send(req);

        expect(seen.headers[Canonical.headerTimestamp], c.timestamp);
        expect(seen.headers[Canonical.headerNonce], c.nonce);
        expect(seen.bodyBytes, utf8.encode(c.body));
        // ECDSA is randomised, so compare by verifying, not by equality.
        expect(serverWouldAccept(seen), isTrue);
        if (c.target == '/v1/devices/pair') {
          expect(seen.headers.containsKey(Canonical.headerDevice), isFalse);
        } else {
          expect(seen.headers[Canonical.headerDevice], 'dev_123');
        }
      });
    }

    test('fresh timestamp and nonce per request', () async {
      final seen = <http.Request>[];
      final client = SigningClient(
        signer: signer,
        deviceId: 'dev_123',
        inner: MockClient((req) async {
          seen.add(req);
          return http.Response('', 204);
        }),
      );
      for (var i = 0; i < 3; i++) {
        await client.send(
          http.Request('GET', Uri.parse('https://vouch.example/v1/devices/me')),
        );
      }
      final nonces = seen.map((r) => r.headers[Canonical.headerNonce]).toSet();
      expect(nonces, hasLength(3));
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      for (final r in seen) {
        final ts = int.parse(r.headers[Canonical.headerTimestamp]!);
        expect((ts - now).abs(), lessThan(5));
        expect(serverWouldAccept(r), isTrue);
      }
    });

    test('keeps the caller\'s headers (content type) alongside ours', () async {
      late http.Request seen;
      final client = SigningClient(
        signer: signer,
        deviceId: 'dev_123',
        inner: MockClient((req) async {
          seen = req;
          return http.Response('', 204);
        }),
      );
      await client.send(
        http.Request(
            'PUT',
            Uri.parse('https://vouch.example/v1/devices/me/push-token'),
          )
          ..headers['Content-Type'] = 'application/json'
          ..body = '{"push_token":"t"}',
      );
      expect(seen.headers['Content-Type'], startsWith('application/json'));
      expect(serverWouldAccept(seen), isTrue);
    });
  });

  group('VouchApi (generated client over the signing transport)', () {
    test('GET /v1/requests/pending?limit=20 signs the query too', () async {
      late http.Request seen;
      final api = VouchApi(
        serverUrl: Uri.parse('https://vouch.example/'),
        signer: signer,
        deviceId: 'dev_123',
        inner: MockClient((req) async {
          seen = req;
          return http.Response(
            jsonEncode({
              'requests': [
                {
                  'request_id': '3f9c2a7b1d4e8f60',
                  'kind': 'sign_in',
                  'agent': 'Scout',
                  'site': 'shop.example.com',
                  'login_title': 'Example',
                  'created_at': '2026-11-04T17:40:00Z',
                  'expires_at': '2026-11-04T17:45:00Z',
                  'state': 'pending',
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      final page = await api.requests.listPendingRequests(limit: 20);
      expect(Canonical.target(seen.url), '/v1/requests/pending?limit=20');
      expect(seen.method, 'GET');
      expect(seen.bodyBytes, isEmpty);
      expect(serverWouldAccept(seen), isTrue);
      expect(page!.requests, hasLength(1));
      expect(page.requests.first.agent, 'Scout');
      expect(page.requests.first.loginTitle, 'Example');
      expect(page.requests.first.expiresAt, DateTime.utc(2026, 11, 4, 17, 45));
    });

    test('POST decision signs the exact JSON body the client sends', () async {
      late http.Request seen;
      final api = VouchApi(
        serverUrl: Uri.parse('https://vouch.example'),
        signer: signer,
        deviceId: 'dev_123',
        inner: MockClient((req) async {
          seen = req;
          return http.Response(
            jsonEncode({
              'request_id': '3f9c2a7b1d4e8f60',
              'kind': 'sign_in',
              'agent': 'Scout',
              'site': 'shop.example.com',
              'login_title': null,
              'created_at': '2026-11-04T17:40:00Z',
              'expires_at': '2026-11-04T17:45:00Z',
              'state': 'once',
              'decided_at': '2026-11-04T17:41:00Z',
              'decided_by': 'this_device',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      final result = await api.requests.decideRequest(
        '3f9c2a7b1d4e8f60',
        DecisionRequest(
          decision: DecisionRequestDecisionEnum.once,
          shownDigest:
              '3b5f3b5f3b5f3b5f3b5f3b5f3b5f3b5f3b5f3b5f3b5f3b5f3b5f3b5f3b5f3b5f',
        ),
      );
      expect(
        Canonical.target(seen.url),
        '/v1/requests/3f9c2a7b1d4e8f60/decision',
      );
      expect(
        utf8.decode(seen.bodyBytes),
        '{"decision":"once","shown_digest":"3b5f3b5f3b5f3b5f3b5f3b5f3b5f3b5f3b5f3b5f3b5f3b5f3b5f3b5f3b5f3b5f"}',
      );
      expect(serverWouldAccept(seen), isTrue);
      expect(result!.state, ApprovalRequestStateEnum.once);
      expect(result.decidedBy, ApprovalRequestDecidedByEnum.thisDevice);
      expect(result.loginTitle, isNull);
    });

    test('409 surfaces as ApiException with the conflict body', () async {
      final api = VouchApi(
        serverUrl: Uri.parse('https://vouch.example'),
        signer: signer,
        deviceId: 'dev_123',
        inner: MockClient(
          (req) async => http.Response(
            '{"code":"already_decided","message":"Another device answered first.","request":{}}',
            409,
          ),
        ),
      );
      await expectLater(
        api.requests.decideRequest(
          '3f9c2a7b1d4e8f60',
          DecisionRequest(
            decision: DecisionRequestDecisionEnum.deny,
            shownDigest:
                '3b5f3b5f3b5f3b5f3b5f3b5f3b5f3b5f3b5f3b5f3b5f3b5f3b5f3b5f3b5f3b5f',
          ),
        ),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 409)),
      );
    });
  });
}
