import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:income_expense_tracker/core/theme/app_theme.dart';
import 'package:income_expense_tracker/core/theme/responsive.dart';

/// Regression guard for a crash that shipped past the rest of the suite.
///
/// Every other widget test pumps without ScreenUtilInit, so the text scale is
/// exactly 1.0 — and `TextTheme.apply(fontSizeFactor: 1.0)` is a no-op that
/// never trips its own assertion. The app on a real device scales by
/// something other than 1.0, which blew up on the first frame. So these build
/// the theme at a scale that is deliberately NOT 1.0.
void main() {
  Future<ThemeData> buildThemeAt(
    WidgetTester tester,
    Size size,
    ThemeData Function() build,
  ) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    late ThemeData theme;
    await tester.pumpWidget(ScreenUtilInit(
      designSize: Responsive.designSize,
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (context, _) {
        theme = build();
        return MaterialApp(theme: theme, home: const SizedBox.shrink());
      },
    ));
    await tester.pump();
    return theme;
  }

  for (final brightness in Brightness.values) {
    final name = brightness.name;
    final build =
        brightness == Brightness.light ? AppTheme.light : AppTheme.dark;

    testWidgets('$name theme builds on a device larger than the design size',
        (tester) async {
      // 720x1600 => scale 2.0, i.e. fontSizeFactor != 1.0.
      final theme = await buildThemeAt(tester, const Size(720, 1600), build);

      expect(tester.takeException(), isNull);
      expect(theme.textTheme.bodyMedium?.fontSize, isNotNull);
    });

    testWidgets('$name theme builds on a device smaller than the design size',
        (tester) async {
      final theme = await buildThemeAt(tester, const Size(320, 640), build);

      expect(tester.takeException(), isNull);
      expect(theme.textTheme.bodyMedium?.fontSize, isNotNull);
    });
  }

  testWidgets('type actually scales with the screen', (tester) async {
    final small = await buildThemeAt(
        tester, const Size(360, 800), AppTheme.light);
    final smallSize = small.textTheme.bodyMedium!.fontSize!;

    final large = await buildThemeAt(
        tester, const Size(720, 1600), AppTheme.light);
    final largeSize = large.textTheme.bodyMedium!.fontSize!;

    expect(largeSize, greaterThan(smallSize),
        reason: 'text should grow on a bigger screen');
  });

  testWidgets('styles without an explicit size survive scaling',
      (tester) async {
    // The crash came from a TextStyle with a null fontSize being handed to
    // TextTheme.apply. Scaling must skip those rather than assert.
    final theme =
        await buildThemeAt(tester, const Size(720, 1600), AppTheme.light);

    expect(tester.takeException(), isNull);
    expect(theme.textTheme.labelSmall, isNotNull);
  });
}
