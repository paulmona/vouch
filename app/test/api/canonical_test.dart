import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:vouch/api/canonical.dart';

import 'test_vectors.dart';

void main() {
  final vectors = TestVectors.load();

  group('canonical string matches the contract vectors', () {
    for (final c in vectors.cases) {
      test(c.name, () {
        final body = utf8.encode(c.body);
        expect(Canonical.bodySha256Hex(body), c.bodySha256Hex);
        expect(
          Canonical.string(
            method: c.method,
            target: c.target,
            bodySha256: Canonical.bodySha256Hex(body),
            timestamp: c.timestamp,
            nonce: c.nonce,
          ),
          c.canonical,
        );
      });
    }
  });

  group('target', () {
    test('path only', () {
      expect(
        Canonical.target(Uri.parse('https://h.example/v1/devices/me')),
        '/v1/devices/me',
      );
    });
    test('path with query, exactly as sent', () {
      expect(
        Canonical.target(
          Uri.parse('https://h.example/v1/requests/pending?limit=20'),
        ),
        '/v1/requests/pending?limit=20',
      );
    });
    test('never includes host or fragment', () {
      expect(
        Canonical.target(Uri.parse('https://h.example:8443/v1/x?a=1#frag')),
        '/v1/x?a=1',
      );
    });
  });

  group('timestamp and nonce', () {
    test('timestamp is unix seconds as a decimal string', () {
      expect(
        Canonical.timestamp(DateTime.utc(2026, 11, 4, 17, 40)),
        '1793814000',
      );
    });
    test('nonce is 22 chars of base64url without padding', () {
      final n = Canonical.nonce();
      expect(n, hasLength(22));
      expect(n, matches(RegExp(r'^[A-Za-z0-9_-]{22}$')));
      expect(Canonical.base64UrlDecode(n), hasLength(16));
    });
    test('nonces do not repeat', () {
      final seen = {for (var i = 0; i < 1000; i++) Canonical.nonce()};
      expect(seen, hasLength(1000));
    });
    test('nonce is deterministic for a seeded Random (tests only)', () {
      expect(Canonical.nonce(Random(1)), Canonical.nonce(Random(1)));
    });
  });

  test('base64url round trip without padding', () {
    for (final len in [0, 1, 2, 3, 16, 32, 71]) {
      final bytes = List<int>.generate(len, (i) => (i * 37) & 0xff);
      final s = Canonical.base64UrlNoPad(bytes);
      expect(s, isNot(contains('=')));
      expect(Canonical.base64UrlDecode(s), bytes);
    }
  });
}
