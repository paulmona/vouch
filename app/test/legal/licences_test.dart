import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vouch/legal/licences.dart';

// The app ships Vouch's own LICENSE and NOTICE (Apache 2.0 asks for the
// NOTICE to travel with every copy) and shows them under Open-source
// licences, next to the bundled fonts' licences.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the bundled LICENSE and NOTICE are the repository\'s, unchanged', () {
    for (final name in ['LICENSE', 'NOTICE']) {
      expect(
        File('assets/legal/$name').readAsStringSync(),
        File('../$name').readAsStringSync(),
        reason: 'app/assets/legal/$name differs from the repository root',
      );
    }
  });

  test(
    'Open-source licences lists Vouch with its licence and notice',
    () async {
      registerLicences();
      final vouch = <String>[];
      await for (final entry in LicenseRegistry.licenses) {
        if (entry.packages.contains('Vouch')) {
          vouch.add(entry.paragraphs.map((p) => p.text).join('\n'));
        }
      }
      expect(vouch.join('\n'), contains('Apache License'));
      expect(vouch.join('\n'), contains('Copyright 2026'));
      final all = <String>{};
      await for (final entry in LicenseRegistry.licenses) {
        all.addAll(entry.packages);
      }
      expect(all, containsAll(['Inter', 'Instrument Serif', 'Vouch']));
    },
  );
}
