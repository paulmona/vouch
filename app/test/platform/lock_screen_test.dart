import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Answering a request needs the phone unlocked: no activity is declared or
// switched at run time to show over the lock screen or turn the screen on,
// so nobody holding a locked phone can reach the request screen.
void main() {
  const main = 'android/app/src/main';

  test('no activity is declared to show over the lock screen', () {
    final manifest = File('$main/AndroidManifest.xml').readAsStringSync();
    expect(
      manifest,
      isNot(contains(RegExp(r'android:showWhenLocked\s*=\s*"true"'))),
    );
    expect(
      manifest,
      isNot(contains(RegExp(r'android:turnScreenOn\s*=\s*"true"'))),
    );
  });

  test('no code turns showing over the lock screen on at run time', () {
    final sources = Directory(main)
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.kt') || f.path.endsWith('.java'));
    for (final f in sources) {
      final text = f.readAsStringSync();
      expect(
        text,
        isNot(
          contains(
            RegExp(
              r'setShowWhenLocked\(\s*true|setTurnScreenOn\(\s*true|'
              r'FLAG_SHOW_WHEN_LOCKED|FLAG_DISMISS_KEYGUARD|FLAG_TURN_SCREEN_ON',
            ),
          ),
        ),
        reason: f.path,
      );
    }
  });

  // A full-screen intent only exists to put an activity over the lock
  // screen. Nothing here may do that, so the permission and the screen
  // that offered it are gone too.
  test('no full-screen intent permission is requested', () {
    final manifest = File('$main/AndroidManifest.xml').readAsStringSync();
    expect(manifest, isNot(contains('USE_FULL_SCREEN_INTENT')));
    expect(manifest, isNot(contains('full-screen')));
  });

  test('no screen promises a request opens over the lock screen', () {
    final sources = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));
    for (final f in sources) {
      final text = f.readAsStringSync();
      expect(text, isNot(contains('over the lock screen')), reason: f.path);
      // Nothing here is full-screen any more: not the notification, not
      // the way a request opens.
      expect(
        text,
        isNot(contains(RegExp('full[- ]screen', caseSensitive: false))),
        reason: f.path,
      );
      expect(
        text,
        isNot(contains('requestFullScreenIntentPermission')),
        reason: f.path,
      );
    }
  });
}
