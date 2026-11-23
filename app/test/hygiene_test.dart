import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Source under lib/ and test/ says what code does, not which private review
// asked for it, and example phone numbers stay in the range reserved for
// fiction (555-0100 to 555-0199).
void main() {
  final files = [
    for (final dir in ['lib', 'test'])
      ...Directory(dir)
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart')),
  ];

  test('no comment cites a security review', () {
    final citation = RegExp(
      r'[(]review\b|\breview [AB]-?\d',
      caseSensitive: false,
    );
    for (final f in files) {
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        expect(
          citation.hasMatch(lines[i]),
          isFalse,
          reason: '${f.path}:${i + 1}: ${lines[i].trim()}',
        );
      }
    }
  });

  test('every 555 number is in the reserved 555-0100..0199 range', () {
    // 555 as an exchange, then four digits, with any common separator.
    final number = RegExp(r'(?<!\d)555[ .-]?(\d{4})(?!\d)');
    for (final f in files) {
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        for (final m in number.allMatches(lines[i])) {
          final line = int.parse(m[1]!);
          expect(
            line >= 100 && line <= 199,
            isTrue,
            reason: '${f.path}:${i + 1}: ${m[0]}',
          );
        }
      }
    }
  });
}
