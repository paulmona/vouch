import '../platform/biometry.dart';
import 'device_key.dart';

/// The decision key is gone (removing the screen lock deletes it), so
/// nothing can be approved until the phone is paired again.
const noDecisionKeyText =
    'This phone no longer has its approval key. Forget this server in Settings, then pair again.';

/// What to tell the owner when the decision key would not sign, or null
/// when they cancelled the prompt themselves (nothing to say).
String? keyErrorText(DeviceKeyException e) => switch (e.error) {
  DeviceKeyError.cancelled => null,
  DeviceKeyError.keyInvalidated =>
    '${Biometry.changedNotice} Pair with your server again.',
  DeviceKeyError.lockout =>
    'Too many failed attempts. Wait a moment and try again.',
  DeviceKeyError.noneEnrolled => '${Biometry.setupHint} to approve requests.',
  DeviceKeyError.noKey => noDecisionKeyText,
  _ => e.message,
};
