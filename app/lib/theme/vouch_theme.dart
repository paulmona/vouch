import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'brand.dart';

/// Material 3 theme seeded from the brand accent, then pinned to the brand
/// palette so the primary stays `#c2410c` (light) / `#ea580c` (dark) rather
/// than the tonal-palette approximation `fromSeed` would pick.
abstract final class VouchTheme {
  static ThemeData light() {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: Brand.accent,
          brightness: Brightness.light,
          dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
        ).copyWith(
          primary: Brand.accent,
          onPrimary: Colors.white,
          primaryContainer: Brand.accentLight,
          onPrimaryContainer: Brand.accentDeep,
          secondary: Brand.logoNavy,
          onSecondary: Colors.white,
          secondaryContainer: const Color(0xFFE2E8F0),
          onSecondaryContainer: Brand.navy,
          surface: Brand.subtle,
          onSurface: Brand.navy,
          onSurfaceVariant: Brand.stone,
          surfaceContainerLowest: Colors.white,
          surfaceContainerLow: const Color(0xFFF5F5F4),
          surfaceContainer: const Color(0xFFF0EFEE),
          surfaceContainerHigh: const Color(0xFFEAE9E7),
          surfaceContainerHighest: const Color(0xFFE4E3E1),
          outline: const Color(0xFF8A8580),
          outlineVariant: const Color(0xFFD6D3D1),
        );
    return _build(scheme);
  }

  static ThemeData dark() {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: Brand.accent,
          brightness: Brightness.dark,
          dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
        ).copyWith(
          primary: Brand.accentWarm,
          onPrimary: Brand.navy,
          primaryContainer: Brand.accentDeep,
          onPrimaryContainer: const Color(0xFFFFEDD5),
          secondary: const Color(0xFFCBD5E1),
          onSecondary: Brand.navy,
          secondaryContainer: const Color(0xFF334155),
          onSecondaryContainer: const Color(0xFFE2E8F0),
          surface: Brand.navy,
          onSurface: const Color(0xFFF8FAFC),
          onSurfaceVariant: const Color(0xFFCBD5E1),
          surfaceContainerLowest: const Color(0xFF0B1220),
          surfaceContainerLow: const Color(0xFF162033),
          surfaceContainer: Brand.slate,
          surfaceContainerHigh: const Color(0xFF273449),
          surfaceContainerHighest: const Color(0xFF334155),
          outline: const Color(0xFF64748B),
          outlineVariant: const Color(0xFF334155),
        );
    return _build(scheme);
  }

  static ThemeData _build(ColorScheme scheme) {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: Brand.fontFamily,
    );
    final text = _textTheme(base.textTheme);
    final isDark = scheme.brightness == Brightness.dark;

    const shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(12)),
    );
    const buttonPadding = EdgeInsets.symmetric(horizontal: 24, vertical: 16);
    const buttonMinSize = Size(64, 56);

    return base.copyWith(
      textTheme: text,
      scaffoldBackgroundColor: scheme.surface,
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 1,
        centerTitle: false,
        titleTextStyle: text.titleLarge,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
          systemNavigationBarColor: Colors.transparent,
          systemNavigationBarIconBrightness: isDark
              ? Brightness.light
              : Brightness.dark,
          systemNavigationBarContrastEnforced: false,
        ),
      ),
      cardTheme: CardThemeData(
        color: scheme.surfaceContainerLow,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: scheme.outlineVariant),
        ),
        margin: EdgeInsets.zero,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: shape,
          padding: buttonPadding,
          minimumSize: buttonMinSize,
          textStyle: text.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: shape,
          padding: buttonPadding,
          minimumSize: buttonMinSize,
          textStyle: text.labelLarge,
          side: BorderSide(color: scheme.outline),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(shape: shape, textStyle: text.labelLarge),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: scheme.onSurfaceVariant,
        titleTextStyle: text.bodyLarge,
        subtitleTextStyle: text.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: shape,
        backgroundColor: isDark ? scheme.surfaceContainerHighest : Brand.navy,
        contentTextStyle: text.bodyMedium?.copyWith(color: Colors.white),
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surfaceContainer,
        indicatorColor: scheme.primaryContainer,
        labelTextStyle: WidgetStatePropertyAll(text.labelMedium),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
        },
      ),
    );
  }

  /// Inter throughout. Headings and labels carry more weight than Material's
  /// defaults so the request screen reads clearly at a glance.
  static TextTheme _textTheme(TextTheme base) {
    TextStyle? w(TextStyle? s, FontWeight weight, {double? letterSpacing}) =>
        s?.copyWith(
          fontFamily: Brand.fontFamily,
          fontWeight: weight,
          letterSpacing: letterSpacing,
        );
    return base.copyWith(
      displayLarge: w(base.displayLarge, FontWeight.w800, letterSpacing: -1),
      displayMedium: w(
        base.displayMedium,
        FontWeight.w800,
        letterSpacing: -0.5,
      ),
      displaySmall: w(base.displaySmall, FontWeight.w700, letterSpacing: -0.5),
      headlineLarge: w(
        base.headlineLarge,
        FontWeight.w700,
        letterSpacing: -0.5,
      ),
      headlineMedium: w(base.headlineMedium, FontWeight.w700),
      headlineSmall: w(base.headlineSmall, FontWeight.w600),
      titleLarge: w(base.titleLarge, FontWeight.w600),
      titleMedium: w(base.titleMedium, FontWeight.w600),
      titleSmall: w(base.titleSmall, FontWeight.w600),
      bodyLarge: w(base.bodyLarge, FontWeight.w400),
      bodyMedium: w(base.bodyMedium, FontWeight.w400),
      bodySmall: w(base.bodySmall, FontWeight.w400),
      labelLarge: w(base.labelLarge, FontWeight.w600),
      labelMedium: w(base.labelMedium, FontWeight.w600),
      labelSmall: w(base.labelSmall, FontWeight.w500),
    );
  }
}

/// WCAG 2 contrast ratio between two opaque colours.
double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final lighter = la > lb ? la : lb;
  final darker = la > lb ? lb : la;
  return (lighter + 0.05) / (darker + 0.05);
}
