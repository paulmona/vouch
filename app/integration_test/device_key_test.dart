// Exercises the real DeviceKeyChannel on a device or simulator: Secure
// Enclave on iOS, Android Keystore on Android. The biometric key needs a
// match; on the iOS simulator enrol Face ID (Features > Face ID > Enrolled)
// and send a match while the prompt is up:
//   xcrun simctl spawn booted notifyutil -p com.apple.BiometricKit_Sim.pearl.match
//
//   flutter test integration_test/device_key_test.dart -d <device>
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:vouch/api/device_signer.dart';
import 'package:vouch/keys/device_key.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final keys = DeviceKeyStore();
  final challenge = Uint8List.fromList(List.generate(32, (i) => i));
  final message = Uint8List.fromList('hello vouch'.codeUnits);

  const spkiPrefix = [
    0x30, 0x59, 0x30, 0x13, 0x06, 0x07, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02, //
    0x01, 0x06, 0x08, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07, 0x03, //
    0x42, 0x00,
  ];

  testWidgets('transport key: generate, inspect, sign, verify, delete', (
    t,
  ) async {
    const alias = 'itest.transport';
    final k = await keys.generate(
      alias: alias,
      challenge: challenge,
      requireUserAuth: false,
    );
    expect(k.publicKeySpki.length, 91);
    expect(k.publicKeySpki.sublist(0, 26), spkiPrefix);
    expect(k.userAuthRequired, isFalse);
    expect(await keys.exists(alias), isTrue);
    expect(await keys.publicKeySpki(alias), k.publicKeySpki);
    final info = await keys.info(alias);
    expect(info.userAuthRequired, isFalse);
    // ignore: avoid_print
    print('transport key in secure hardware: ${info.strongBox}');

    final sig = await keys.sign(
      alias: alias,
      message: message,
      prompt: const PromptText(title: 'itest'),
    );
    expect(
      EcdsaVerifier.fromSpki(k.publicKeySpki).verify(message, sig),
      isTrue,
    );
    expect(
      EcdsaVerifier.fromSpki(
        k.publicKeySpki,
      ).verify(Uint8List.fromList('other'.codeUnits), sig),
      isFalse,
    );

    await keys.delete(alias);
    expect(await keys.exists(alias), isFalse);
    await expectLater(
      keys.publicKeySpki(alias),
      throwsA(
        isA<DeviceKeyException>().having(
          (e) => e.error,
          'error',
          DeviceKeyError.noKey,
        ),
      ),
    );
  });

  testWidgets(
    'decision key: biometric-bound signature verifies',
    (t) async {
      const alias = 'itest.decision';
      final status = await keys.biometricStatus();
      // ignore: avoid_print
      print('biometricStatus: $status');
      expect(status, BiometricStatus.available);

      final k = await keys.generate(
        alias: alias,
        challenge: challenge,
        requireUserAuth: true,
      );
      expect(k.userAuthRequired, isTrue);
      expect((await keys.info(alias)).userAuthRequired, isTrue);

      final sig = await keys.sign(
        alias: alias,
        message: message,
        prompt: const PromptText(title: 'Confirm approval', subtitle: 'itest'),
      );
      expect(
        EcdsaVerifier.fromSpki(k.publicKeySpki).verify(message, sig),
        isTrue,
      );
      await keys.delete(alias);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
