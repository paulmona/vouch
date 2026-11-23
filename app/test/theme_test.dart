import 'package:flutter_test/flutter_test.dart';
import 'package:vouch/theme/brand.dart';
import 'package:vouch/theme/vouch_theme.dart';

void main() {
  group('brand colours stay in charge', () {
    test('light primary is the brand accent', () {
      expect(VouchTheme.light().colorScheme.primary, Brand.accent);
    });
    test('dark primary is accent-warm', () {
      expect(VouchTheme.dark().colorScheme.primary, Brand.accentWarm);
    });
    test('Inter is the text font', () {
      expect(VouchTheme.light().textTheme.bodyLarge?.fontFamily, 'Inter');
    });
  });

  // WCAG AA: 4.5:1 for normal text, 3:1 for large text and UI components.
  group('contrast (WCAG AA)', () {
    for (final (name, theme) in [
      ('light', VouchTheme.light()),
      ('dark', VouchTheme.dark()),
    ]) {
      final s = theme.colorScheme;
      test('$name: text on surface', () {
        expect(contrastRatio(s.onSurface, s.surface), greaterThan(4.5));
        expect(contrastRatio(s.onSurfaceVariant, s.surface), greaterThan(4.5));
      });
      test('$name: filled button text on primary', () {
        expect(contrastRatio(s.onPrimary, s.primary), greaterThan(4.5));
      });
      test('$name: primary as text on surface', () {
        expect(contrastRatio(s.primary, s.surface), greaterThan(4.5));
      });
      test('$name: tonal button text on primary container', () {
        expect(
          contrastRatio(s.onPrimaryContainer, s.primaryContainer),
          greaterThan(4.5),
        );
      });
      test('$name: outline against surface (UI component)', () {
        expect(contrastRatio(s.outline, s.surface), greaterThan(3));
      });
    }
  });
}
