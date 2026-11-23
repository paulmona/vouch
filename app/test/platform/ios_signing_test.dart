import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// The app target takes its signing from xcconfig variables so that a CI build
// can sign by hand with its own certificate and profile. A plain local build,
// with nothing in VouchLocal.xcconfig, must still let Xcode manage signing.
void main() {
  final project = File(
    'ios/Runner.xcodeproj/project.pbxproj',
  ).readAsStringSync();
  final defaults = File('ios/Flutter/Vouch.xcconfig').readAsStringSync();

  // The build settings of each configuration of the app target: the blocks
  // that set the app's bundle id.
  final appConfigs = RegExp(r'buildSettings = \{([\s\S]*?)\n\t\t\t\};')
      .allMatches(project)
      .map((m) => m.group(1)!)
      .where(
        (s) => s.contains(r'PRODUCT_BUNDLE_IDENTIFIER = "$(VOUCH_BUNDLE_ID)"'),
      )
      .toList();

  test('every configuration of the app target signs from the variables', () {
    expect(appConfigs, hasLength(3)); // Debug, Release, Profile
    for (final s in appConfigs) {
      expect(s, contains(r'CODE_SIGN_STYLE = "$(VOUCH_CODE_SIGN_STYLE)";'));
      expect(
        s,
        contains(
          r'"CODE_SIGN_IDENTITY[sdk=iphoneos*]" = "$(VOUCH_CODE_SIGN_IDENTITY)";',
        ),
      );
      expect(
        s,
        contains(
          r'"PROVISIONING_PROFILE_SPECIFIER[sdk=iphoneos*]" = "$(VOUCH_PROFILE_SPECIFIER)";',
        ),
      );
      expect(s, contains(r'DEVELOPMENT_TEAM = "$(VOUCH_DEVELOPMENT_TEAM)";'));
    }
  });

  test('without VouchLocal.xcconfig, Xcode manages signing', () {
    String value(String name) {
      final m = RegExp('^$name *=(.*)\$', multiLine: true).firstMatch(defaults);
      expect(m, isNotNull, reason: '$name has no default in Vouch.xcconfig');
      return m!.group(1)!.trim();
    }

    expect(value('VOUCH_CODE_SIGN_STYLE'), 'Automatic');
    expect(value('VOUCH_CODE_SIGN_IDENTITY'), 'iPhone Developer');
    expect(value('VOUCH_PROFILE_SPECIFIER'), '');
    // The defaults come before the local file, so the local file wins.
    expect(
      defaults.indexOf('VOUCH_CODE_SIGN_STYLE'),
      lessThan(defaults.indexOf('#include? "VouchLocal.xcconfig"')),
    );
  });
}
