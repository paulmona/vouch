import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// The request-signing scheme from `api/openapi.yaml`, implemented exactly.
///
/// The device signs this canonical string, five parts joined by a single LF,
/// no trailing newline:
///
/// ```
/// METHOD        upper case, e.g. POST
/// TARGET        path plus query string exactly as sent
/// BODY_SHA256   lower-case hex SHA-256 of the exact body bytes ("" if none)
/// TIMESTAMP     Unix seconds, decimal string (X-Vouch-Timestamp)
/// NONCE         X-Vouch-Nonce
/// ```
abstract final class Canonical {
  static const headerDevice = 'X-Vouch-Device';
  static const headerTimestamp = 'X-Vouch-Timestamp';
  static const headerNonce = 'X-Vouch-Nonce';
  static const headerSignature = 'X-Vouch-Signature';

  /// Lower-case hex SHA-256 of the exact body bytes.
  static String bodySha256Hex(List<int> body) =>
      sha256.convert(body).toString();

  /// The request target: path plus query string exactly as sent, e.g.
  /// `/v1/requests/pending?limit=20`. Never includes scheme, host or fragment.
  static String target(Uri uri) =>
      uri.hasQuery ? '${uri.path}?${uri.query}' : uri.path;

  /// Builds the canonical string. [bodySha256] is the hex digest, so callers
  /// that already hashed the body do not hash it twice.
  static String string({
    required String method,
    required String target,
    required String bodySha256,
    required String timestamp,
    required String nonce,
  }) => '${method.toUpperCase()}\n$target\n$bodySha256\n$timestamp\n$nonce';

  /// Unix seconds as a decimal string.
  static String timestamp(DateTime now) =>
      (now.toUtc().millisecondsSinceEpoch ~/ 1000).toString();

  /// 16 random bytes, base64url without padding (22 characters).
  static String nonce([Random? random]) {
    final r = random ?? Random.secure();
    final bytes = Uint8List.fromList(
      List<int>.generate(16, (_) => r.nextInt(256)),
    );
    return base64UrlNoPad(bytes);
  }

  /// base64url without padding, as the contract requires everywhere.
  static String base64UrlNoPad(List<int> bytes) =>
      base64Url.encode(bytes).replaceAll('=', '');

  /// Decodes base64url with or without padding.
  static Uint8List base64UrlDecode(String s) {
    final padded = s.padRight((s.length + 3) ~/ 4 * 4, '=');
    return base64Url.decode(padded);
  }
}
