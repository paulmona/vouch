import 'package:flutter/material.dart';

/// Viewbridge brand tokens, read from https://viewbridge.ai (CSS and logo)
/// on 2026-11-04. Brand colours win over dynamic (wallpaper) colour: a
/// security prompt must always look like Vouch.
abstract final class Brand {
  /// Primary brand colour: the logo square, primary actions (light theme).
  static const accent = Color(0xFFC2410C);

  /// Hover and pressed states, highlights, and the dark-theme primary
  /// (accent itself fails AA on navy; accent-warm passes).
  static const accentWarm = Color(0xFFEA580C);

  /// Tinted surfaces and containers.
  static const accentLight = Color(0xFFFFF7ED);

  /// Deep accent for text on accent-light containers.
  static const accentDeep = Color(0xFF7C2D12);

  /// Primary text and dark surfaces.
  static const navy = Color(0xFF0F172A);

  /// Wordmark text and the logo's inner diamond.
  static const logoNavy = Color(0xFF1A2744);

  /// Secondary dark surfaces.
  static const slate = Color(0xFF1E293B);

  /// Secondary text.
  static const stone = Color(0xFF78716C);
  static const stoneCool = Color(0xFF6B7280);

  /// Light background.
  static const subtle = Color(0xFFFAFAF9);

  static const fontFamily = 'Inter';

  /// Decorative only; at most one use (the tagline).
  static const serifFamily = 'InstrumentSerif';

  static const productName = 'Vouch';
  static const fullName = 'Vouch by Viewbridge';
  static const tagline = 'Context is everything.';
}
