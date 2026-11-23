import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// A published build must not carry anyone's Firebase config, so the iOS build
// cannot require GoogleService-Info.plist. It is copied into the app only when
// it is there, and a build without it leaves none behind from an earlier one.
void main() {
  final project = File(
    'ios/Runner.xcodeproj/project.pbxproj',
  ).readAsStringSync();

  test('the Firebase config is not a required resource of the app', () {
    expect(project, isNot(contains('GoogleService-Info.plist in Resources')));
  });

  test('a build phase copies it only when it exists, and removes a stale '
      'copy otherwise', () {
    final phase = RegExp(
      r'/\* Firebase Config If Present \*/ = \{([\s\S]*?)\n\t\t\};',
    ).firstMatch(project);
    expect(phase, isNotNull, reason: 'no "Firebase Config If Present" phase');
    final script = phase!.group(1)!;
    expect(script, contains('isa = PBXShellScriptBuildPhase;'));
    expect(script, contains(r'if [ -f \"$src\" ]; then'));
    expect(script, contains(r'cp \"$src\" \"$dst\"'));
    expect(script, contains(r'rm -f \"$dst\"'));

    // It belongs to the app target, after its resources are copied.
    final phases = RegExp(
      r'buildPhases = \(([^)]*)\);',
    ).allMatches(project).map((m) => m.group(1)!);
    final app = phases.singleWhere((p) => p.contains('Thin Binary'));
    expect(
      app.indexOf('/* Firebase Config If Present */'),
      greaterThan(app.indexOf('/* Resources */')),
    );
  });
}
