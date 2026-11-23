import '../api/vouch_api_client.dart';
import '../sms/phone_format.dart';
import '../text/shown_text.dart';

/// Wording shared by every screen that names what a request asks for.
extension RequestKind on ApprovalRequest {
  /// The agent's name, site and login title as the phone shows them:
  /// anything hidden or out of place is marked, never trusted.
  String get shownAgent => ShownText.oneLine(agent);
  String get shownSite => ShownText.host(site);
  String? get shownLoginTitle =>
      loginTitle == null ? null : ShownText.oneLine(loginTitle!);

  /// The reason an agent gave for texting someone new.
  String? get shownReason =>
      smsContact == null ? null : ShownText.oneLine(smsContact!.reason);

  /// An agent asking to text someone new.
  bool get isSmsContact =>
      kind == ApprovalRequestKindEnum.smsContact && smsContact != null;

  /// The number the agent wants to text, as people read it. This, not the
  /// name the agent chose, is what approving permits.
  String get shownNumber =>
      ShownText.oneLine(formatPhone(smsContact?.phone ?? site));

  /// The name the agent gave the contact, or null when it gave none.
  String? get shownContactName {
    final name = smsContact?.name;
    if (name == null || name.trim().isEmpty) return null;
    return ShownText.oneLine(name);
  }

  /// "text (204) 555-0150", "sign in to shop.example.com", ...: what
  /// approving allows. Always the number: the agent chooses the name, and
  /// could make it look like another number.
  String get allows =>
      isSmsContact ? 'text $shownNumber' : 'sign in to $shownSite';

  /// Only sign-ins can be allowed for good; the contract refuses `always`
  /// for anything else.
  bool get canAlways => !isSmsContact;
}
