import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vouch/api/canonical.dart';
import 'package:vouch/api/device_signer.dart';
import 'package:vouch/dev/sample_requests.dart';
import 'package:vouch/keys/device_key.dart';
import 'package:vouch/model/decision.dart';
import 'package:vouch/pairing/paired_device.dart';
import 'package:vouch/push/notifications.dart';
import 'package:vouch/requests/decision_service.dart';
import 'package:vouch/requests/shown_digest.dart';
import 'package:vouch_api/api.dart';

import '../helpers/fake_keys.dart';

class _Notifier implements RequestNotifier {
  final cleared = <String>[];
  @override
  Future<void> clearRequest(String requestId) async => cleared.add(requestId);
  @override
  Future<void> showRequest(
    String requestId, {
    String? title,
    String? body,
  }) async {}
  @override
  Future<void> showAlert(String alertId, {String? title, String? body}) async {}
}

class _ThrowingNotifier extends _Notifier {
  var attempts = 0;
  @override
  Future<void> clearRequest(String requestId) async {
    attempts++;
    throw StateError('plugin gone');
  }
}

void main() {
  final t0 = DateTime.utc(2026, 11, 4, 22);
  final paired = PairedDevice(
    deviceId: 'dev_0123456789',
    serverUrl: Uri.parse('https://vouch.example.com'),
    serverName: 'h',
    requireUserAuth: true,
    userAuthBound: 'attested',
    pairedAt: t0,
  );
  final request = SampleRequests.signIn(now: t0);

  Future<FakeKeys> keysWithBoth({bool cancel = false}) async {
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

  http.Response decided(String state) => http.Response(
    jsonEncode({
      ...request.toJson(),
      'state': state,
      'decided_at': '2026-11-04T22:01:00Z',
      'decided_by': 'this_device',
    }),
    200,
    headers: {'content-type': 'application/json'},
  );

  test('the server\'s answer survives a failing onDecided or clear', () async {
    final keys = await keysWithBoth();
    final notifier = _ThrowingNotifier();
    final s = DecisionService(
      keys: keys,
      paired: paired,
      notifier: notifier,
      httpClient: () => MockClient((r) async => decided('once')),
      // What a disposed Riverpod ref does: throws.
      onDecided: () => throw StateError('ref disposed'),
    );
    final outcome = await s.decide(request, Decision.once);
    expect(outcome, isA<Approved>());
    expect(notifier.attempts, 1, reason: 'clearing was still tried');
  });

  test(
    'Approve once: decision key signs, prompt names agent and site, body is exact',
    () async {
      final keys = await keysWithBoth();
      final notifier = _Notifier();
      late http.Request seen;
      var decidedCalls = 0;
      final s = DecisionService(
        keys: keys,
        paired: paired,
        notifier: notifier,
        httpClient: () => MockClient((r) async {
          seen = r;
          return decided('once');
        }),
        onDecided: () => decidedCalls++,
      );
      final outcome = await s.decide(request, Decision.once);

      expect(
        outcome,
        isA<Approved>().having((a) => a.decision, 'decision', Decision.once),
      );
      expect(seen.method, 'POST');
      expect(seen.url.path, '/v1/requests/${request.requestId}/decision');
      expect(
        utf8.decode(seen.bodyBytes),
        '{"decision":"once","shown_digest":"${shownDigest(request)}"}',
      );
      expect(seen.headers[Canonical.headerDevice], 'dev_0123456789');

      // Signed by the DECISION key, after one prompt with the right words.
      expect(keys.prompts.single.title, 'Approve once');
      expect(keys.prompts.single.subtitle, 'shop.example.com, asked by Scout');
      final canonical = Canonical.string(
        method: 'POST',
        target: seen.url.path,
        bodySha256: Canonical.bodySha256Hex(seen.bodyBytes),
        timestamp: seen.headers[Canonical.headerTimestamp]!,
        nonce: seen.headers[Canonical.headerNonce]!,
      );
      final decisionSpki = await keys.publicKeySpki(
        DeviceKeyStore.decisionAlias,
      );
      final transportSpki = await keys.publicKeySpki(
        DeviceKeyStore.transportAlias,
      );
      final sig = Canonical.base64UrlDecode(
        seen.headers[Canonical.headerSignature]!,
      );
      final msg = Uint8List.fromList(canonical.codeUnits);
      expect(EcdsaVerifier.fromSpki(decisionSpki).verify(msg, sig), isTrue);
      expect(EcdsaVerifier.fromSpki(transportSpki).verify(msg, sig), isFalse);

      expect(notifier.cleared, [request.requestId]);
      expect(decidedCalls, 1);
    },
  );

  test('sms_contact: the prompt names who the agent wants to text', () async {
    final keys = await keysWithBoth();
    final s = DecisionService(
      keys: keys,
      paired: paired,
      notifier: _Notifier(),
      httpClient: () => MockClient((_) async => decided('once')),
    );
    await s.decide(SampleRequests.smsContact(), Decision.once);
    expect(keys.prompts.single.title, 'Approve');
    expect(
      keys.prompts.single.subtitle,
      'Text (204) 555-0150 (Sam), asked by Ava',
    );
  });

  // Each decision has its own prompt title, so a Deny tap and an approval
  // never look the same at the moment of Face ID.
  test('the prompt names the decision it confirms', () async {
    final titles = <String>[];
    for (final (d, state) in [
      (Decision.once, 'once'),
      (Decision.always, 'always'),
      (Decision.deny, 'deny'),
    ]) {
      final keys = await keysWithBoth();
      await DecisionService(
        keys: keys,
        paired: paired,
        notifier: _Notifier(),
        httpClient: () => MockClient((_) async => decided(state)),
      ).decide(request, d);
      titles.add(keys.prompts.single.title);
      expect(keys.prompts.single.subtitle, 'shop.example.com, asked by Scout');
    }
    expect(titles, ['Approve once', 'Always allow', 'Deny']);
  });

  test('the prompt puts the site before a long agent name', () {
    // The fingerprint sheet cuts its subtitle at the end; the agent's own
    // name must not be what pushes the site off it.
    final r = request;
    final long = ApprovalRequest(
      requestId: r.requestId,
      kind: r.kind,
      agent: 'Research assistant for the quarterly planning and budget reviews',
      site: r.site,
      loginTitle: r.loginTitle,
      createdAt: r.createdAt,
      expiresAt: r.expiresAt,
      state: r.state,
    );
    expect(
      DecisionService.promptFor(long, Decision.once).subtitle,
      startsWith('shop.example.com'),
    );
    expect(
      DecisionService.promptFor(
        SampleRequests.smsContact(),
        Decision.once,
      ).subtitle,
      startsWith('Text (204) 555-0150'),
    );
  });

  test('Always allow and Deny map to their outcomes', () async {
    for (final (d, state, matcher) in [
      (
        Decision.always,
        'always',
        isA<Approved>().having((a) => a.decision, 'decision', Decision.always),
      ),
      (Decision.deny, 'deny', isA<Denied>()),
    ]) {
      final s = DecisionService(
        keys: await keysWithBoth(),
        paired: paired,
        notifier: _Notifier(),
        httpClient: () => MockClient((r) async => decided(state)),
      );
      expect(await s.decide(request, d), matcher);
    }
  });

  test('cancelling the fingerprint prompt sends nothing', () async {
    var calls = 0;
    final notifier = _Notifier();
    final s = DecisionService(
      keys: await keysWithBoth(cancel: true),
      paired: paired,
      notifier: notifier,
      httpClient: () => MockClient((r) async {
        calls++;
        return decided('once');
      }),
    );
    expect(await s.decide(request, Decision.once), isA<Cancelled>());
    expect(calls, 0);
    expect(notifier.cleared, isEmpty);
  });

  test(
    'a decision key that is gone says to pair again, and sends nothing',
    () async {
      var calls = 0;
      final keys = await keysWithBoth();
      await keys.delete(DeviceKeyStore.decisionAlias);
      final outcome = await DecisionService(
        keys: keys,
        paired: paired,
        notifier: _Notifier(),
        httpClient: () => MockClient((r) async {
          calls++;
          return decided('once');
        }),
      ).decide(request, Decision.once);
      expect(
        outcome,
        isA<Failed>().having(
          (f) => f.message,
          'message',
          'This phone no longer has its approval key. '
              'Forget this server in Settings, then pair again.',
        ),
      );
      expect(calls, 0);
    },
  );

  group('a reply that does not confirm the decision is an error', () {
    final replies = <String, http.Response Function()>{
      'empty 200': () => http.Response('', 200),
      'empty 204': () => http.Response('', 204),
      'redirect with no body': () => http.Response(
        '',
        302,
        headers: {'location': 'https://login.example.com/'},
      ),
      'empty JSON object': () => http.Response(
        '{}',
        200,
        headers: {'content-type': 'application/json'},
      ),
      'another request': () => http.Response(
        jsonEncode({
          ...request.toJson(),
          'request_id': '0000000000000000',
          'state': 'once',
        }),
        200,
        headers: {'content-type': 'application/json'},
      ),
      'still pending': () => decided('pending'),
      'a different decision': () => decided('always'),
    };
    for (final MapEntry(key: name, value: reply) in replies.entries) {
      for (final d in [Decision.once, Decision.deny]) {
        test('$name, ${d.name}', () async {
          final notifier = _Notifier();
          var decidedCalls = 0;
          final outcome = await DecisionService(
            keys: await keysWithBoth(),
            paired: paired,
            notifier: notifier,
            httpClient: () => MockClient((_) async => reply()),
            onDecided: () => decidedCalls++,
          ).decide(request, d);
          expect(outcome, isA<Failed>(), reason: '$outcome');
          // Unconfirmed: the notification stays and nothing is refetched.
          expect(notifier.cleared, isEmpty);
          expect(decidedCalls, 0);
        });
      }
    }
  });

  group('409 from the server', () {
    for (final (code, matcher) in [
      ('already_decided', isA<AnsweredElsewhere>()),
      ('expired', isA<Expired>()),
    ]) {
      test(code, () async {
        final notifier = _Notifier();
        final s = DecisionService(
          keys: await keysWithBoth(),
          paired: paired,
          notifier: notifier,
          httpClient: () => MockClient(
            (r) async => http.Response(
              jsonEncode({
                'code': code,
                'message': 'late',
                'request': request.toJson(),
              }),
              409,
            ),
          ),
        );
        expect(await s.decide(request, Decision.once), matcher);
        // Either way the request is over: take the notification down.
        expect(notifier.cleared, [request.requestId]);
      });
    }
  });

  test(
    '409 shown_mismatch: the newer request comes back, still pending',
    () async {
      final notifier = _Notifier();
      final changed = {...request.toJson(), 'site': 'other.example.com'};
      final s = DecisionService(
        keys: await keysWithBoth(),
        paired: paired,
        notifier: notifier,
        httpClient: () => MockClient(
          (r) async => http.Response(
            jsonEncode({
              'code': 'shown_mismatch',
              'message': 'changed',
              'request': changed,
            }),
            409,
          ),
        ),
      );
      expect(
        await s.decide(request, Decision.once),
        isA<ShownChanged>().having(
          (c) => c.request.site,
          'site',
          'other.example.com',
        ),
      );
      // Not settled: the notification stays.
      expect(notifier.cleared, isEmpty);
    },
  );

  test(
    '422 and connection failures are Failed with a message, not thrown',
    () async {
      final s422 = DecisionService(
        keys: await keysWithBoth(),
        paired: paired,
        notifier: _Notifier(),
        httpClient: () => MockClient(
          (r) async => http.Response(
            jsonEncode({
              'code': 'policy_requires_user_auth',
              'message': 'Pair it again.',
            }),
            422,
          ),
        ),
      );
      expect(
        await s422.decide(request, Decision.once),
        isA<Failed>().having((f) => f.message, 'message', 'Pair it again.'),
      );
      final sNet = DecisionService(
        keys: await keysWithBoth(),
        paired: paired,
        notifier: _Notifier(),
        httpClient: () =>
            MockClient((r) async => throw http.ClientException('refused')),
      );
      expect(await sNet.decide(request, Decision.deny), isA<Failed>());
    },
  );
}
