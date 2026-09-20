import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Proportional sizing, built on flutter_screenutil.
///
/// The design size is a 360x800 logical phone — the common Android portrait
/// size and what this app was laid out against. Values scale from there, so a
/// chart that fills a 5" screen fills a 6.7" one in the same proportion
/// instead of leaving a band of empty space.
class Responsive {
  const Responsive._();

  /// The canvas every hard-coded dimension in this app is expressed against.
  static const designSize = Size(360, 800);

  /// True once [ScreenUtilInit] has run. Widget tests pump bare widgets with
  /// no initializer, so every helper below falls back to the raw value rather
  /// than throwing — a missing initializer degrades to "unscaled", never to a
  /// crash in front of a user.
  /// Factor applied to every font size in the theme. 1.0 before init.
  ///
  /// Computed here rather than read from `ScreenUtil().scaleText` so the
  /// behaviour is guaranteed: always the *smaller* of the two axes. Scaling
  /// text by width alone makes it balloon on a wide screen.
  static double get textScale {
    try {
      if (!isReady) return 1.0;
      final util = ScreenUtil();
      return math.min(util.scaleWidth, util.scaleHeight);
    } catch (_) {
      return 1.0;
    }
  }

  static bool get isReady {
    try {
      return ScreenUtil().screenWidth > 0;
    } catch (_) {
      return false;
    }
  }
}

/// Scaled sizing helpers that are safe before initialization.
extension ResponsiveSize on num {
  /// Width-proportional. Use for horizontal gaps and widths.
  double get rw => Responsive.isReady ? ScreenUtil().setWidth(this) : toDouble();

  /// Height-proportional. Use for vertical gaps and fixed block heights.
  double get rh =>
      Responsive.isReady ? ScreenUtil().setHeight(this) : toDouble();

  /// Scales by the smaller axis. Use for anything that must stay square or
  /// circular — icons, avatars, corner radii — so it never distorts.
  double get rr => Responsive.isReady ? ScreenUtil().radius(this) : toDouble();

  /// Text. Scales by the smaller axis, so it grows on larger screens without
  /// running away on wide ones.
  double get rsp => toDouble() * Responsive.textScale;
}
