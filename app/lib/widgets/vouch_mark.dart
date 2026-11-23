import 'package:flutter/material.dart';

import '../theme/brand.dart';

/// The Viewbridge mark: a rounded orange square holding a white diamond with
/// a navy inner diamond. Drawn, not an image, so it is crisp at any size.
/// Matches the Android adaptive icon.
class VouchMark extends StatelessWidget {
  const VouchMark({super.key, this.size = 48, this.semanticLabel});

  final double size;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      image: semanticLabel != null,
      excludeSemantics: semanticLabel == null,
      child: CustomPaint(
        size: Size.square(size),
        painter: const _MarkPainter(),
      ),
    );
  }
}

class _MarkPainter extends CustomPainter {
  const _MarkPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 32; // the logo is drawn on a 32-unit square
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(6 * s)),
      Paint()..color = Brand.accent,
    );
    final c = Offset(16 * s, 16 * s);
    canvas.drawPath(
      _diamond(c, 8 * s),
      Paint()..color = Colors.white.withValues(alpha: 0.9),
    );
    canvas.drawPath(_diamond(c, 4 * s), Paint()..color = Brand.logoNavy);
  }

  Path _diamond(Offset c, double r) => Path()
    ..moveTo(c.dx, c.dy - r)
    ..lineTo(c.dx + r, c.dy)
    ..lineTo(c.dx, c.dy + r)
    ..lineTo(c.dx - r, c.dy)
    ..close();

  @override
  bool shouldRepaint(_MarkPainter oldDelegate) => false;
}
