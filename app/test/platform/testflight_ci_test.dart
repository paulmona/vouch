import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// A published iPhone build must carry no Firebase config. testflight.sh --ci
// builds the published one, so it must stop where a GoogleService-Info.plist
// is present. The script runs in a copy of its folder layout, so a real
// config file in this checkout is never touched.
void main() {
  late Directory root;
  late File key;

  setUp(() {
    root = Directory.systemTemp.createTempSync('vouch-testflight-');
    Directory('${root.path}/app/tool').createSync(recursive: true);
    Directory('${root.path}/app/ios/Runner').createSync(recursive: true);
    Directory('${root.path}/app/ios/Flutter').createSync(recursive: true);
    File('tool/testflight.sh').copySync('${root.path}/app/tool/testflight.sh');
    File(
      '${root.path}/app/pubspec.yaml',
    ).writeAsStringSync('name: vouch\nversion: 9.8.7+1\n');
    key = File('${root.path}/key.p8')..writeAsStringSync('not a key');
  });

  tearDown(() => root.deleteSync(recursive: true));

  ProcessResult ci() => Process.runSync(
    'bash',
    ['${root.path}/app/tool/testflight.sh', '--ci', '--dry-run'],
    environment: {
      'VOUCH_DEVELOPMENT_TEAM': 'ABCDE12345',
      // No installed profile has this name, so a run that gets past the
      // Firebase check stops at the profile check, before any build.
      'IOS_PROFILE_NAME': 'no profile has this name',
      'ASC_KEY_ID': 'TESTKEY000',
      'ASC_ISSUER_ID': '00000000-0000-0000-0000-000000000000',
      'ASC_KEY_PATH': key.path,
    },
  );

  const refused = 'a published build carries no Firebase config';

  test('--ci refuses to build with a Firebase config present', () {
    File(
      '${root.path}/app/ios/Runner/GoogleService-Info.plist',
    ).writeAsStringSync('<plist/>');
    final r = ci();
    expect(r.exitCode, isNot(0));
    expect(r.stderr as String, contains(refused));
  });

  test('--ci goes past that check when there is none', () {
    final r = ci();
    expect(r.exitCode, isNot(0)); // no certificate or profile here
    expect(r.stderr as String, isNot(contains(refused)));
  });
}
