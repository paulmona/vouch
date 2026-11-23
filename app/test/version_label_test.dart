import 'package:flutter_test/flutter_test.dart';
import 'package:vouch/screens/about_screen.dart';

void main() {
  test('version label carries the baked-in commit when there is one', () {
    expect(
      versionLabel('0.1.0', '10100', '3f2a9c1'),
      '0.1.0 (10100) · 3f2a9c1',
    );
    expect(versionLabel('0.1.0', '1', ''), '0.1.0 (1)');
  });
}
