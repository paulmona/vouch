import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vouch/api/canonical.dart';
import 'package:vouch/api/device_signer.dart';
import 'package:vouch/api/signing_client.dart';

import 'test_vectors.dart';

void main() {
  final vectors = TestVectors.load();
  final signer = SoftwareSigner.fromPkcs8Pem(vectors.privateKeyPkcs8Pem);
  final phoneNow = DateTime.utc(2026, 11, 5, 1, 0, 0);
  // The server is 5 minutes ahead of the phone: well outside ±60 s.
  final serverNow = phoneNow.add(const Duration(minutes: 5));

  http.Response skew() => http.Response(
    jsonEncode({
      'code': 'clock_skew',
      'message': 'Check the time on your phone.',
      'server_time': serverNow.toIso8601String(),
    }),
    401,
    headers: {'content-type': 'application/json'},
  );

  test('401 clock_skew: learns the offset, re-signs, retries once', () async {
    final seen = <http.Request>[];
    final clock = ServerClock();
    final client = SigningClient(
      signer: signer,
      deviceId: 'dev_0123456789',
      clock: () => phoneNow,
      serverClock: clock,
      inner: MockClient((r) async {
        seen.add(r);
        return seen.length == 1 ? skew() : http.Response('{"ok":1}', 200);
      }),
    );

    final res = await client.get(
      Uri.parse('https://vouch.example.com/v1/devices/me'),
    );

    expect(res.statusCode, 200);
    expect(seen, hasLength(2));
    expect(
      seen[0].headers[Canonical.headerTimestamp],
      Canonical.timestamp(phoneNow),
    );
    expect(
      seen[1].headers[Canonical.headerTimestamp],
      Canonical.timestamp(serverNow),
      reason: 'the retry carries the corrected timestamp',
    );
    expect(
      seen[1].headers[Canonical.headerNonce],
      isNot(seen[0].headers[Canonical.headerNonce]),
      reason: 'a fresh nonce, never a replay',
    );
    expect(clock.offset, const Duration(minutes: 5));

    // The retried request is signed over the corrected timestamp.
    final r = seen[1];
    final canonical = Canonical.string(
      method: r.method,
      target: Canonical.target(r.url),
      bodySha256: Canonical.bodySha256Hex(r.bodyBytes),
      timestamp: r.headers[Canonical.headerTimestamp]!,
      nonce: r.headers[Canonical.headerNonce]!,
    );
    final ok =
        EcdsaVerifier.fromSpki(
          Canonical.base64UrlDecode(vectors.publicKeySpkiB64url),
        ).verify(
          Uint8List.fromList(canonical.codeUnits),
          Canonical.base64UrlDecode(r.headers[Canonical.headerSignature]!),
        );
    expect(ok, isTrue);
  });

  test(
    'the learnt offset is used by the next client to the same server',
    () async {
      final clock = ServerClock()..offset = const Duration(seconds: -90);
      http.Request? seen;
      final client = SigningClient(
        signer: signer,
        deviceId: 'dev_0123456789',
        clock: () => phoneNow,
        serverClock: clock,
        inner: MockClient((r) async {
          seen = r;
          return http.Response('', 204);
        }),
      );
      await client.get(Uri.parse('https://vouch.example.com/v1/devices/me'));
      expect(
        seen!.headers[Canonical.headerTimestamp],
        Canonical.timestamp(phoneNow.subtract(const Duration(seconds: 90))),
      );
    },
  );

  test('a second clock_skew in a row is returned, not retried again', () async {
    var calls = 0;
    final client = SigningClient(
      signer: signer,
      deviceId: 'dev_0123456789',
      clock: () => phoneNow,
      serverClock: ServerClock(),
      inner: MockClient((r) async {
        calls++;
        return skew();
      }),
    );
    final res = await client.get(
      Uri.parse('https://vouch.example.com/v1/devices/me'),
    );
    expect(res.statusCode, 401);
    expect(calls, 2);
  });

  test('other 401s pass through untouched with their body', () async {
    var calls = 0;
    final client = SigningClient(
      signer: signer,
      deviceId: 'dev_0123456789',
      clock: () => phoneNow,
      serverClock: ServerClock(),
      inner: MockClient((r) async {
        calls++;
        return http.Response(
          '{"code":"unknown_device","message":"Pair again."}',
          401,
        );
      }),
    );
    final res = await client.get(
      Uri.parse('https://vouch.example.com/v1/devices/me'),
    );
    expect(res.statusCode, 401);
    expect(jsonDecode(res.body)['code'], 'unknown_device');
    expect(calls, 1);
  });

  test('POST bodies are re-sent byte for byte on the retry', () async {
    final seen = <http.Request>[];
    final client = SigningClient(
      signer: signer,
      deviceId: 'dev_0123456789',
      clock: () => phoneNow,
      serverClock: ServerClock(),
      inner: MockClient((r) async {
        seen.add(r);
        return seen.length == 1 ? skew() : http.Response('', 204);
      }),
    );
    await client.post(
      Uri.parse('https://vouch.example.com/v1/devices/me/checkin'),
      headers: {'content-type': 'application/json'},
      body: '{"heartbeat_id":"hb_1"}',
    );
    expect(seen[1].body, '{"heartbeat_id":"hb_1"}');
    expect(seen[1].headers['content-type'], startsWith('application/json'));
  });
}
