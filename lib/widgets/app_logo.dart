import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

/// The Accounts Note brand mark.
///
/// An "A" whose apex is an arrowhead and whose crossbar is a ledger rule,
/// sitting on a baseline. Drawn as vectors rather than loaded from a PNG, so
/// it stays crisp at any size — a 24px app bar and a 1024px store icon come
/// from the same code.
class AppLogo extends StatelessWidget {
  final double size;

  /// Rounded tile with a drop shadow. Off for exports, where the platform
  /// applies its own mask and shadow.
  final bool rounded;

  /// Solid brand colour instead of the gradient. Used for flat contexts such
  /// as an Android adaptive-icon foreground.
  final bool flat;

  /// Shrinks the mark into the adaptive-icon safe zone.
  ///
  /// Android masks launcher icons to a circle/squircle and only guarantees the
  /// central ~66% is visible, so an export drawn edge-to-edge gets its
  /// extremities clipped. In-app the tile is never masked, so this stays off.
  final bool safeZone;

  const AppLogo({
    super.key,
    this.size = 72,
    this.rounded = true,
    this.flat = false,
    this.safeZone = false,
  });

  @override
  Widget build(BuildContext context) {
    final radius =
        rounded ? BorderRadius.circular(size * 0.235) : BorderRadius.zero;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: flat
            ? null
            : const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.brandDeep, AppColors.brand, Color(0xFF14B8A6)],
              ),
        color: flat ? AppColors.brand : null,
        boxShadow: rounded
            ? [
                BoxShadow(
                  color: AppColors.brandDeep.withValues(alpha: 0.22),
                  blurRadius: size * 0.22,
                  offset: Offset(0, size * 0.08),
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: CustomPaint(
          size: Size.square(size),
          painter: _AppLogoMarkPainter(
            contentScale: safeZone ? 0.66 : 1.0,
          ),
          isComplex: false,
        ),
      ),
    );
  }
}

/// Paints the mark on a unit square scaled to [size].
///
/// Geometry is expressed as fractions of the tile so the proportions hold at
/// every size instead of drifting.
class _AppLogoMarkPainter extends CustomPainter {
  /// 1.0 draws edge-to-edge; below that the mark shrinks toward the centre.
  final double contentScale;
  final Color color;

  const _AppLogoMarkPainter({
    this.contentScale = 1.0,
    this.color = Colors.white,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    Offset p(double x, double y) => Offset(x * s, y * s);

    if (contentScale != 1.0) {
      final centre = s / 2;
      canvas.translate(centre, centre);
      canvas.scale(contentScale);
      canvas.translate(-centre, -centre);
    }

    // A ledger that trends upward: two ruled lines with a rising line above
    // them. No letterforms, so nothing tightens up at launcher sizes.

    // The rules sit back at partial opacity so the trend line stays the
    // subject rather than competing with them.
    final rule = Paint()
      ..color = color.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true
      ..strokeWidth = 0.070 * s;

    canvas.drawLine(p(0.250, 0.700), p(0.750, 0.700), rule);
    // Shorter second rule: an even pair would read as an equals sign.
    canvas.drawLine(p(0.250, 0.818), p(0.570, 0.818), rule);

    // One path with round joins, so the corners of the zigzag stay smooth
    // instead of throwing mitre spikes where the direction reverses.
    final trend = Path()
      ..moveTo(p(0.258, 0.548).dx, p(0.258, 0.548).dy)
      ..lineTo(p(0.438, 0.348).dx, p(0.438, 0.348).dy)
      ..lineTo(p(0.578, 0.470).dx, p(0.578, 0.470).dy)
      ..lineTo(p(0.778, 0.232).dx, p(0.778, 0.232).dy);

    canvas.drawPath(
      trend,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..isAntiAlias = true
        ..strokeWidth = 0.096 * s,
    );
  }

  @override
  bool shouldRepaint(covariant _AppLogoMarkPainter oldDelegate) =>
      oldDelegate.contentScale != contentScale || oldDelegate.color != color;
}

/// The mark alone, with no tile behind it.
///
/// For surfaces that supply their own background — notably the Android 12
/// splash, where the system fills a circle and masks whatever image it is
/// given. Handing that a full tile gets the corners and the extremities of
/// the mark clipped, so the splash export uses this instead.
class AppLogoMark extends StatelessWidget {
  final double size;
  final Color color;

  /// Fraction of the canvas the mark occupies. The splash mask is tighter
  /// than the launcher-icon mask, so exports for it scale down further.
  final double contentScale;

  const AppLogoMark({
    super.key,
    this.size = 72,
    this.color = Colors.white,
    this.contentScale = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        size: Size.square(size),
        painter: _AppLogoMarkPainter(
          contentScale: contentScale,
          color: color,
        ),
      ),
    );
  }
}
