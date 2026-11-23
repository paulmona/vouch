import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../api/cloudflare_access.dart';
import '../api/vouch_api_client.dart';
import '../keys/device_key.dart';
import '../keys/key_error_text.dart';
import '../keys/keystore_signer.dart';
import '../model/decision.dart';
import '../pairing/device_session.dart';
import '../pairing/paired_device.dart';
import '../push/notifications.dart';
import 'request_kind.dart';
import 'shown_digest.dart';

/// Signs and posts a decision with the **decision key**: one fingerprint
/// prompt naming the decision and the request (see [promptFor]), then
/// `POST /v1/requests/{id}/decision`. Cancelling the prompt sends nothing.
class DecisionService {
  DecisionService({
    required this.keys,
    required this.paired,
    required this.notifier,
    http.Client Function()? httpClient,
    this.onDecided,
  }) : _httpClient = httpClient ?? http.Client.new;

  final DeviceKeyStore keys;
  final PairedDevice paired;
  final RequestNotifier notifier;
  final http.Client Function() _httpClient;

  /// Called after the server settled the request (any outcome but
  /// Cancelled or Failed), so lists can refetch.
  final void Function()? onDecided;

  /// The fingerprint sheet says which decision it confirms, in the words
  /// of the button pressed, and for what, so a Deny tap can never stand in
  /// for an approval.
  static PromptText promptFor(ApprovalRequest request, Decision decision) =>
      PromptText(
        title: switch (decision) {
          Decision.once => request.isSmsContact ? 'Approve' : 'Approve once',
          Decision.always => 'Always allow',
          Decision.deny => 'Deny',
        },
        // Where it applies comes first: the sheet cuts a long line at the
        // end, and the agent picks its own (long) names. For a text that is
        // the number; the contact's name is the agent's and comes second.
        subtitle: request.isSmsContact
            ? 'Text ${request.shownNumber}'
                  '${switch (request.shownContactName) {
                    null => '',
                    final n => ' ($n)',
                  }}, asked by ${request.shownAgent}'
            : '${request.shownSite}, asked by ${request.shownAgent}',
      );

  static const unconfirmedMessage =
      "Your server's reply did not confirm the decision. Open the request "
      'again to see where it stands.';

  /// [request] must be exactly what the screen displayed: its digest is
  /// signed with the decision.
  Future<DecisionOutcome> decide(
    ApprovalRequest request,
    Decision decision,
  ) async {
    final api = VouchApi(
      serverUrl: paired.serverUrl,
      deviceId: paired.deviceId,
      signer: KeystoreSigner(
        store: keys,
        alias: DeviceKeyStore.decisionAlias,
        prompt: promptFor(request, decision),
      ),
      inner: _httpClient(),
    );
    try {
      final r = await api.requests.decideRequest(
        request.requestId,
        DecisionRequest(
          decision: decision.toApi(),
          shownDigest: shownDigest(request),
        ),
      );
      // Only the request itself, settled the way it was asked, confirms the
      // decision. An empty or unexpected reply (a proxy's redirect, a
      // login page) says nothing about what the server recorded.
      final confirmed =
          r != null &&
          r.requestId == request.requestId &&
          r.state == decision.toApiState();
      if (!confirmed) return const Failed(unconfirmedMessage);
      // The server has the decision from here on; nothing below may lose it.
      await _settled(request.requestId);
      return decision == Decision.deny ? const Denied() : Approved(decision);
    } on DeviceKeyException catch (e) {
      return _fromKeyError(e);
    } on ApiException catch (e) {
      // The generated client wraps anything thrown while sending, including
      // the Keystore's refusal to sign without a fingerprint.
      if (e.innerException case final DeviceKeyException inner) {
        return _fromKeyError(inner);
      }
      if (isAccessBlocked(e)) return const Failed(accessBlockedMessage);
      if (e.innerException != null) {
        return const Failed(
          "Couldn't reach your server. Check the connection and try again.",
        );
      }
      final body = _json(e.message);
      final code = body['code'] as String?;
      final message = body['message'] as String?;
      if (e.code == 409 && code == 'shown_mismatch') {
        // Still pending on the server: nothing to clear.
        if (ApprovalRequest.fromJson(body['request']) case final current?) {
          return ShownChanged(current);
        }
        return const Failed('This request changed. Open it again.');
      }
      if (e.code == 409) {
        await _settled(request.requestId);
        return code == 'expired' ? const Expired() : const AnsweredElsewhere();
      }
      return Failed(message ?? 'The server refused the decision (${e.code}).');
    } on http.ClientException catch (e) {
      if (isAccessBlocked(e)) return const Failed(accessBlockedMessage);
      return Failed("Couldn't reach your server: ${e.message}");
    } on Object catch (e) {
      // A reply the generated client could not read as a request: it
      // confirms nothing.
      debugPrint('Vouch: unreadable decision reply (${e.runtimeType})');
      return const Failed(unconfirmedMessage);
    } finally {
      api.close();
    }
  }

  static DecisionOutcome _fromKeyError(DeviceKeyException e) =>
      switch (keyErrorText(e)) {
        null => const Cancelled(),
        final text => Failed(text),
      };

  /// Best effort after the server settled the request: take the
  /// notification down and let Home know. Neither may turn an accepted
  /// decision into an error on screen (a throwing [onDecided]
  /// left the spinner on for good).
  Future<void> _settled(String requestId) async {
    try {
      await notifier.clearRequest(requestId);
    } on Object catch (e) {
      debugPrint('Vouch: could not clear the notification (${e.runtimeType})');
    }
    try {
      onDecided?.call();
    } on Object catch (e) {
      debugPrint('Vouch: onDecided failed (${e.runtimeType})');
    }
  }

  static Map<String, Object?> _json(String? s) {
    try {
      return (jsonDecode(s ?? '') as Map<String, Object?>?) ?? const {};
    } on Object {
      return const {};
    }
  }
}

/// A [DecisionService] for the current pairing, or null when not paired.
final decisionServiceProvider = Provider<DecisionService?>((ref) {
  // Only the identity matters. Watching the whole pairing rebuilt this
  // provider on every last-contact update, including the ones the app
  // triggers on resume after the fingerprint prompt, and the service then
  // in the middle of a decision was left with a disposed ref.
  final (deviceId, serverUrl) = ref.watch(
    pairedDeviceProvider.select((p) => (p.value?.deviceId, p.value?.serverUrl)),
  );
  if (deviceId == null || serverUrl == null) return null;
  final paired = ref.read(pairedDeviceProvider).value;
  if (paired == null) return null;
  return DecisionService(
    keys: ref.watch(deviceKeyStoreProvider),
    paired: paired,
    notifier: ref.watch(requestNotifierProvider),
    httpClient: ref.watch(httpClientProvider),
    onDecided: () {
      if (ref.mounted) ref.invalidate(pendingRequestsInvalidator);
    },
  );
});

/// Invalidated after a decision so Home's pending list refetches.
final pendingRequestsInvalidator = Provider<int>((ref) => 0);
