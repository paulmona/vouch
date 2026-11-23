import 'package:flutter/services.dart';

/// One number the owner picked in the system contact picker, as Contacts
/// shows it. The server normalises the number.
typedef PickedContact = ({String name, String phone});

/// The iOS contact picker. No contacts permission: the picker runs
/// outside the app and hands back only the chosen number.
class ContactPicker {
  ContactPicker({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName);

  static const channelName = 'ai.viewbridge.vouch/contact_picker';

  final MethodChannel _channel;

  /// Null when the owner cancels.
  Future<PickedContact?> pick() async {
    final r = await _channel.invokeMapMethod<String, String>('pick');
    final phone = r?['phone'];
    if (r == null || phone == null) return null;
    return (name: r['name'] ?? '', phone: phone);
  }
}
