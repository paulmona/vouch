import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vouch/api/vouch_api_client.dart';
import 'package:vouch/requests/shown_digest.dart';

/// The contract's vectors (api/test-vectors.json, "shown_digest"): the app
/// and the server must hash a displayed request identically.
void main() {
  final vectors =
      (jsonDecode(File('../api/test-vectors.json').readAsStringSync())
              as Map<String, Object?>)['shown_digest']!
          as Map<String, Object?>;

  for (final c in (vectors['cases']! as List).cast<Map<String, Object?>>()) {
    test(c['name']! as String, () {
      // Parsed the way a fetched request is, so expires_at goes through
      // DateTime and back.
      final r = ApprovalRequest.fromJson({
        ...(c['request']! as Map<String, Object?>),
        'created_at': '2026-01-01T00:00:00.000Z',
        'state': 'pending',
      })!;
      expect(shownCanonical(r), c['canonical']);
      expect(shownDigest(r), c['shown_digest']);
    });
  }

  // Marking is display only: the digest is over the value the server sent.
  test('the digest is over the raw value, not the marked one', () {
    ApprovalRequest withAgent(String agent) => ApprovalRequest(
      requestId: '3f9c2a7b1d4e8f60',
      kind: ApprovalRequestKindEnum.signIn,
      agent: agent,
      site: 'shop.example.com',
      createdAt: DateTime.utc(2026),
      expiresAt: DateTime.utc(2026, 1, 1, 0, 5),
      state: ApprovalRequestStateEnum.pending,
    );
    final raw = withAgent('Pay\uE000Pal');
    expect(shownCanonical(raw), contains('Pay\uE000Pal'));
    expect(shownDigest(raw), isNot(shownDigest(withAgent('Pay[U+E000]Pal'))));
  });
}
