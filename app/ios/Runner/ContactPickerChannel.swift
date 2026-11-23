import ContactsUI
import Flutter
import UIKit

/// The system contact picker. It runs out of process, so the app
/// needs no contacts permission and sees only the one number the owner
/// picks: `pick` returns `{name, phone}` as shown in Contacts (the server
/// normalises the number), or nil when the owner cancels.
///
/// A contact with one number is picked by tapping it; one with several
/// opens its card so the owner chooses which number.
enum ContactPickerChannel {
  static let name = "ai.viewbridge.vouch/contact_picker"
  /// The picker holds its delegate weakly; this keeps it alive until done.
  private static var active: Delegate?

  static func register(with messenger: FlutterBinaryMessenger) {
    let ch = FlutterMethodChannel(name: name, binaryMessenger: messenger)
    ch.setMethodCallHandler { call, result in
      switch call.method {
      case "pick": pick(result)
      default: result(FlutterMethodNotImplemented)
      }
    }
  }

  private static func pick(_ result: @escaping FlutterResult) {
    guard active == nil, let presenter = topViewController() else {
      result(FlutterError(code: "busy", message: "A picker is already open", details: nil))
      return
    }
    let delegate = Delegate { picked in
      active = nil
      result(picked)
    }
    active = delegate
    let picker = CNContactPickerViewController()
    picker.delegate = delegate
    picker.displayedPropertyKeys = [CNContactPhoneNumbersKey]
    picker.predicateForEnablingContact = NSPredicate(format: "phoneNumbers.@count > 0")
    picker.predicateForSelectionOfContact = NSPredicate(format: "phoneNumbers.@count == 1")
    presenter.present(picker, animated: true)
  }

  private static func topViewController() -> UIViewController? {
    let window = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }
      .first { $0.isKeyWindow }
    var top = window?.rootViewController
    while let presented = top?.presentedViewController { top = presented }
    return top
  }

  private final class Delegate: NSObject, CNContactPickerDelegate {
    let done: ([String: String]?) -> Void
    init(done: @escaping ([String: String]?) -> Void) { self.done = done }

    func contactPickerDidCancel(_ picker: CNContactPickerViewController) { done(nil) }

    // A contact with exactly one number.
    func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
      guard let number = contact.phoneNumbers.first?.value.stringValue else { return done(nil) }
      done(["name": Self.name(of: contact), "phone": number])
    }

    // The number the owner chose on a contact with several.
    func contactPicker(
      _ picker: CNContactPickerViewController, didSelect contactProperty: CNContactProperty
    ) {
      guard let number = (contactProperty.value as? CNPhoneNumber)?.stringValue else {
        return done(nil)
      }
      done(["name": Self.name(of: contactProperty.contact), "phone": number])
    }

    private static func name(of c: CNContact) -> String {
      let full = [c.givenName, c.familyName].filter { !$0.isEmpty }.joined(separator: " ")
      return full.isEmpty ? c.organizationName : full
    }
  }
}
