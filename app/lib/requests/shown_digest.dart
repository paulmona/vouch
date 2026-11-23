import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../api/vouch_api_client.dart';

/// What the request screen displayed, in the contract's fixed order
/// (`DecisionRequest.shown_digest`). The digest goes into the signed
/// decision, so an answer only counts for the request the owner saw.
///
/// Each line is `name=<UTF-8 byte length>:<value>` or `name=-` for null; the
/// length keeps a value with a newline in it unambiguous.
String shownCanonical(ApprovalRequest r) {
  final c = r.smsContact;
  final fields = <(String, String?)>[
    ('request_id', r.requestId),
    ('kind', r.kind.toJson()),
    ('agent', r.agent),
    ('site', r.site),
    ('login_title', r.loginTitle),
    // The server sends JavaScript's toISOString form, which is also what
    // Dart prints for a UTC time with millisecond precision.
    ('expires_at', r.expiresAt.toUtc().toIso8601String()),
    ('sms_phone', c?.phone),
    ('sms_name', c?.name),
    ('sms_reason', c?.reason),
  ];
  final b = StringBuffer('vouch-shown-v1\n');
  for (final (name, value) in fields) {
    b.write(
      value == null
          ? '$name=-\n'
          : '$name=${utf8.encode(value).length}:$value\n',
    );
  }
  return b.toString();
}

/// Lower-case hex SHA-256 of [shownCanonical].
String shownDigest(ApprovalRequest r) =>
    sha256.convert(utf8.encode(shownCanonical(r))).toString();
