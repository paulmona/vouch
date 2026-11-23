import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../api/cloudflare_access.dart';
import '../api/vouch_api_client.dart';
import '../keys/device_key.dart';
import '../keys/key_error_text.dart';
import '../keys/keystore_signer.dart';
import '../pairing/device_session.dart';
import '../pairing/paired_device.dart';
import 'contact_picker.dart';
import 'phone_format.dart';
import 'sms_providers.dart';

/// The permitted contacts: who the agent may text.
final smsContactsProvider = FutureProvider.autoDispose<List<SmsContact>>(
  retry: smsRetry,
  (ref) async {
    final api = ref.watch(transportApiProvider);
    if (api == null) return const [];
    final r = await api.sms.listSmsContacts();
    final list = [...?r?.contacts];
    list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  },
);

/// How a contact change ended.
sealed class ContactChange {
  const ContactChange();
}

class ContactChanged extends ContactChange {
  const ContactChanged();
}

/// The owner dismissed Face ID. Nothing was sent.
class ContactChangeCancelled extends ContactChange {
  const ContactChangeCancelled();
}

class ContactChangeFailed extends ContactChange {
  const ContactChangeFailed(this.message);
  final String message;
}

/// Adds and removes permitted contacts. Each call is signed by the decision
/// key, so it needs Face ID or the fingerprint, the same as a decision.
class SmsContactService {
  SmsContactService({
    required this.keys,
    required this.paired,
    http.Client Function()? httpClient,
  }) : _httpClient = httpClient ?? http.Client.new;

  final DeviceKeyStore keys;
  final PairedDevice paired;
  final http.Client Function() _httpClient;

  /// Permits [phone] as the picker gave it; the server normalises it or
  /// refuses it with a reason (`invalid_number`, `contact_exists`).
  Future<ContactChange> add({required String name, required String phone}) =>
      _signed(
        PromptText(
          title: 'Add $name',
          subtitle: 'Your agent will be able to text $phone',
        ),
        (api) => api.sms.addSmsContact(
          AddSmsContactRequest(phone: phone, name: name),
        ),
      );

  Future<ContactChange> remove(SmsContact contact) => _signed(
    PromptText(
      title: 'Remove ${contact.name}',
      subtitle: 'Your agent will no longer text ${formatPhone(contact.phone)}',
    ),
    (api) => api.sms.removeSmsContact(phonePath(contact.phone)),
    // Already gone (removed on the other phone): the result is the same.
    goneIsDone: true,
  );

  Future<ContactChange> _signed(
    PromptText prompt,
    Future<void> Function(VouchApi api) call, {
    bool goneIsDone = false,
  }) async {
    final api = VouchApi(
      serverUrl: paired.serverUrl,
      deviceId: paired.deviceId,
      signer: KeystoreSigner(
        store: keys,
        alias: DeviceKeyStore.decisionAlias,
        prompt: prompt,
      ),
      inner: _httpClient(),
    );
    try {
      await call(api);
      return const ContactChanged();
    } on DeviceKeyException catch (e) {
      return _keyFailure(e);
    } on ApiException catch (e) {
      // The generated client wraps anything thrown while sending, including
      // a refused or cancelled Face ID.
      if (e.innerException case final DeviceKeyException inner) {
        return _keyFailure(inner);
      }
      if (isAccessBlocked(e)) {
        return const ContactChangeFailed(accessBlockedMessage);
      }
      if (e.innerException != null) {
        return const ContactChangeFailed(
          "Couldn't reach your server. Check the connection and try again.",
        );
      }
      if (e.code == 404 && goneIsDone) return const ContactChanged();
      final message = _message(e.message);
      return ContactChangeFailed(
        message ?? 'The server refused the change (${e.code}).',
      );
    } on http.ClientException catch (e) {
      if (isAccessBlocked(e)) {
        return const ContactChangeFailed(accessBlockedMessage);
      }
      return ContactChangeFailed("Couldn't reach your server: ${e.message}");
    } finally {
      api.close();
    }
  }

  static ContactChange _keyFailure(DeviceKeyException e) =>
      switch (keyErrorText(e)) {
        null => const ContactChangeCancelled(),
        final text => ContactChangeFailed(text),
      };

  /// `SmsError.message` is plain English, safe to show.
  static String? _message(String? body) {
    try {
      final m = jsonDecode(body ?? '');
      return m is Map && m['message'] is String ? m['message'] as String : null;
    } on FormatException {
      return null;
    }
  }
}

final contactPickerProvider = Provider<ContactPicker>((ref) => ContactPicker());

/// A [SmsContactService] for the current pairing, or null when not paired.
final smsContactServiceProvider = Provider<SmsContactService?>((ref) {
  final paired = ref.watch(
    pairedDeviceProvider.select(
      (p) => p.value == null ? null : (p.value!.deviceId, p.value!.serverUrl),
    ),
  );
  final device = ref.read(pairedDeviceProvider).value;
  if (paired == null || device == null) return null;
  return SmsContactService(
    keys: ref.watch(deviceKeyStoreProvider),
    paired: device,
    httpClient: ref.watch(httpClientProvider),
  );
});
