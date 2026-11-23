import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vouch/keys/device_key.dart';
import 'package:vouch/keys/keystore_signer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(DeviceKeyStore.channelName);
  final calls = <MethodCall>[];
  Object? Function(MethodCall call)? handler;

  setUp(() {
    calls.clear();
    handler = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return handler!(call);
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  final store = DeviceKeyStore();
  final spki = Uint8List.fromList(List<int>.generate(91, (i) => i));
  final der = Uint8List.fromList([0x30, 0x45, 1, 2, 3]);

  test('generate passes the challenge and policy, returns the key', () async {
    handler = (c) => {
      'publicKey': spki,
      'attestationChain': [Uint8List(3), Uint8List(4)],
      'strongBox': true,
      'userAuthRequired': true,
    };
    final challenge = Uint8List.fromList(List<int>.filled(32, 7));
    final k = await store.generate(
      alias: DeviceKeyStore.decisionAlias,
      challenge: challenge,
      requireUserAuth: true,
    );
    expect(calls.single.method, 'generate');
    expect(calls.single.arguments, {
      'alias': 'vouch.decision',
      'challenge': challenge,
      'requireUserAuth': true,
    });
    expect(k.publicKeySpki, spki);
    expect(k.attestationChain, hasLength(2));
    expect(k.strongBox, isTrue);
    expect(k.userAuthRequired, isTrue);
  });

  test('sign sends the prompt texts and returns DER', () async {
    handler = (c) => der;
    final msg = Uint8List.fromList('canonical'.codeUnits);
    final sig = await store.sign(
      alias: DeviceKeyStore.decisionAlias,
      message: msg,
      prompt: PromptText.confirmApproval(
        agent: 'Scout',
        site: 'shop.example.com',
      ),
    );
    expect(sig, der);
    expect(calls.single.arguments, {
      'alias': 'vouch.decision',
      'message': msg,
      'title': 'Confirm approval',
      'subtitle': 'Scout at shop.example.com',
      'negativeButton': 'Cancel',
    });
  });

  test('platform errors map to DeviceKeyError', () async {
    for (final (code, expected) in [
      ('cancelled', DeviceKeyError.cancelled),
      ('no_key', DeviceKeyError.noKey),
      ('lockout', DeviceKeyError.lockout),
      ('none_enrolled', DeviceKeyError.noneEnrolled),
      ('key_invalidated', DeviceKeyError.keyInvalidated),
      ('not_authenticated', DeviceKeyError.notAuthenticated),
      ('keystore', DeviceKeyError.other),
      ('biometric', DeviceKeyError.other),
    ]) {
      handler = (c) => throw PlatformException(code: code, message: 'm');
      await expectLater(
        store.sign(
          alias: 'a',
          message: Uint8List(1),
          prompt: const PromptText(title: 't'),
        ),
        throwsA(
          isA<DeviceKeyException>().having((e) => e.error, 'error', expected),
        ),
        reason: code,
      );
    }
  });

  test('biometricStatus maps the strings', () async {
    for (final (s, expected) in [
      ('available', BiometricStatus.available),
      ('none_enrolled', BiometricStatus.noneEnrolled),
      ('no_hardware', BiometricStatus.noHardware),
      ('unavailable', BiometricStatus.unavailable),
      ('???', BiometricStatus.unavailable),
    ]) {
      handler = (c) => s;
      expect(await store.biometricStatus(), expected);
    }
  });

  test('KeystoreSigner signs through the channel with its prompt', () async {
    handler = (c) => c.method == 'sign' ? der : spki;
    final signer = KeystoreSigner(
      store: store,
      alias: DeviceKeyStore.transportAlias,
      prompt: const PromptText(title: 'unused for a plain key'),
    );
    expect(await signer.signDer(Uint8List(2)), der);
    expect(await signer.publicKeySpki(), spki);
    expect(calls.map((c) => c.method), ['sign', 'publicKey']);
    expect(calls.first.arguments['alias'], 'vouch.transport');
  });
}
