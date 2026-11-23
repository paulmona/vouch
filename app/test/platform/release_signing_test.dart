import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// A release build signed with the debug key installs, but cannot update a
// properly signed app and is signed by a key anyone has. Without the upload
// keystore the release build must stop, not fall back.
void main() {
  test('release signing never falls back to the debug key', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    // The buildTypes block, up to its closing brace at four spaces.
    final start = gradle.indexOf('buildTypes {');
    expect(start, isNot(-1), reason: 'buildTypes not found');
    final buildTypes = gradle.substring(
      start,
      gradle.indexOf('\n    }\n', start),
    );
    expect(buildTypes, contains('release {'));
    expect(buildTypes, isNot(contains('getByName("debug")')));
    expect(gradle, contains('GradleException'));
  });
}
