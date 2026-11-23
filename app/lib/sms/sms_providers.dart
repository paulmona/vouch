import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/cloudflare_access.dart';
import '../api/vouch_api_client.dart';
import '../pairing/device_session.dart';

/// The SMS endpoints take an E.164 number in the path. The generated client
/// pastes it in as is, and a `+` must reach the server as `%2B` (contract,
/// `Phone` parameter), so every call goes through this.
String phonePath(String e164) => Uri.encodeComponent(e164);

/// Riverpod retries failed providers; a 4xx (SMS off, bad number) will
/// not fix itself, so only network and server errors are retried.
Duration? smsRetry(int count, Object error) =>
    error is ApiException && error.code >= 400 && error.code < 500
    ? null
    : ProviderContainer.defaultRetry(count, error);

/// One row per number, most recent first. Refetched on open, pull,
/// and an `sms_updated` push.
final smsConversationsProvider =
    FutureProvider.autoDispose<List<SmsConversation>>(retry: smsRetry, (
      ref,
    ) async {
      final api = ref.watch(transportApiProvider);
      if (api == null) return const [];
      final r = await api.sms.listSmsConversations();
      return r?.conversations ?? const [];
    });

/// What a thread screen shows: messages newest first, as the server pages
/// them, plus where the next older page starts.
class SmsThreadState {
  const SmsThreadState({
    this.messages = const [],
    this.nextBefore,
    this.loadingOlder = false,
  });

  final List<SmsMessage> messages;
  final String? nextBefore;
  final bool loadingOlder;

  bool get hasOlder => nextBefore != null;
}

/// One conversation, keyed by E.164 number. The first page marks the thread
/// read on the server, so it is only fetched while the thread is on screen.
final smsThreadProvider = AsyncNotifierProvider.autoDispose
    .family<SmsThread, SmsThreadState, String>(SmsThread.new, retry: smsRetry);

class SmsThread extends AsyncNotifier<SmsThreadState> {
  SmsThread(this.phone);

  final String phone;

  static const pageSize = 50;

  @override
  Future<SmsThreadState> build() async {
    final api = ref.watch(transportApiProvider);
    if (api == null) return const SmsThreadState();
    final page = await api.sms.listSmsMessages(
      phonePath(phone),
      limit: pageSize,
    );
    // Opening the thread just cleared its unread count.
    ref.invalidate(smsConversationsProvider);
    final newest = page?.messages ?? const <SmsMessage>[];
    // A refresh (sms_updated) keeps the older pages already scrolled into.
    final kept = state.value;
    if (kept == null) {
      return SmsThreadState(messages: newest, nextBefore: page?.nextBefore);
    }
    final ids = {for (final m in newest) m.messageId};
    final oldestNew = newest.isEmpty ? null : newest.last.at;
    final older = [
      for (final m in kept.messages)
        if (!ids.contains(m.messageId) &&
            oldestNew != null &&
            m.at.isBefore(oldestNew))
          m,
    ];
    return SmsThreadState(
      messages: [...newest, ...older],
      nextBefore: older.isEmpty ? page?.nextBefore : kept.nextBefore,
    );
  }

  /// Deletes these messages from Vouch. Returns null on success, or
  /// what to tell the owner. Unknown ids are ignored by the server.
  Future<String?> deleteMessages(Set<String> ids) async {
    final api = ref.read(transportApiProvider);
    if (api == null || ids.isEmpty) return null;
    try {
      await api.sms.deleteSmsMessages(
        DeleteSmsMessagesRequest(messageIds: ids),
      );
    } catch (e) {
      return _failure(e);
    }
    final s = state.value;
    if (s != null) {
      state = AsyncData(
        SmsThreadState(
          messages: [
            for (final m in s.messages)
              if (!ids.contains(m.messageId)) m,
          ],
          nextBefore: s.nextBefore,
        ),
      );
    }
    ref.invalidate(smsConversationsProvider);
    return null;
  }

  /// Deletes every message with this number from Vouch. Already gone (404)
  /// counts as done. Returns null on success, or what to tell the owner.
  Future<String?> deleteConversation() async {
    final api = ref.read(transportApiProvider);
    if (api == null) return null;
    try {
      await api.sms.deleteSmsConversation(phonePath(phone));
    } on ApiException catch (e) {
      if (e.code != 404) return _failure(e);
    } catch (e) {
      return _failure(e);
    }
    ref.invalidate(smsConversationsProvider);
    return null;
  }

  static String _failure(Object e) => isAccessBlocked(e)
      ? accessBlockedMessage
      : e is ApiException && e.innerException == null
      ? 'The server refused to delete (${e.code}).'
      : "Couldn't reach your server. Check the connection and try again.";

  /// Appends the next older page. Does nothing while one is loading or when
  /// there is none.
  Future<void> loadOlder() async {
    final s = state.value;
    final api = ref.read(transportApiProvider);
    if (s == null || !s.hasOlder || s.loadingOlder || api == null) return;
    state = AsyncData(
      SmsThreadState(
        messages: s.messages,
        nextBefore: s.nextBefore,
        loadingOlder: true,
      ),
    );
    try {
      final page = await api.sms.listSmsMessages(
        phonePath(phone),
        before: s.nextBefore,
        limit: pageSize,
      );
      state = AsyncData(
        SmsThreadState(
          messages: [...s.messages, ...?page?.messages],
          nextBefore: page?.nextBefore,
        ),
      );
    } catch (_) {
      // Keep what is shown; scrolling up again retries.
      state = AsyncData(s);
    }
  }
}
