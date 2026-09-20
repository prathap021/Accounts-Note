import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:income_expense_tracker/core/theme/responsive.dart';

/// Proportional sizing must scale on real devices *and* degrade to raw values
/// when ScreenUtil was never initialized — otherwise every widget test, and
/// any screen built outside ScreenUtilInit, would throw.
void main() {
  Future<void> pumpAt(WidgetTester tester, Size size, VoidCallback body) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ScreenUtilInit(
      designSize: Responsive.designSize,
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (context, _) => MaterialApp(
        home: Builder(builder: (context) {
          body();
          return const SizedBox.shrink();
        }),
      ),
    ));
    await tester.pump();
  }

  group('without initialization', () {
    test('falls back to the raw value instead of throwing', () {
      expect(Responsive.isReady, isFalse);
      expect(16.rw, 16.0);
      expect(24.rh, 24.0);
      expect(44.rr, 44.0);
      expect(14.rsp, 14.0);
      expect(Responsive.textScale, 1.0);
    });
  });

  group('at the design size', () {
    testWidgets('sizes are unchanged', (tester) async {
      late double width, height, radius, text;
      await pumpAt(tester, const Size(360, 800), () {
        width = 16.rw;
        height = 24.rh;
        radius = 44.rr;
        text = 14.rsp;
      });

      expect(width, closeTo(16, 0.01));
      expect(height, closeTo(24, 0.01));
      expect(radius, closeTo(44, 0.01));
      expect(text, closeTo(14, 0.01));
    });
  });

  group('on a larger screen', () {
    testWidgets('sizes grow proportionally', (tester) async {
      late double width, radius;
      await pumpAt(tester, const Size(720, 1600), () {
        width = 16.rw;
        radius = 44.rr;
      });

      expect(width, closeTo(32, 0.01), reason: 'twice the design width');
      expect(radius, closeTo(88, 0.01), reason: 'square things scale evenly');
    });

    testWidgets('text grows but is capped by the smaller axis',
        (tester) async {
      // A very wide, short screen: text must follow the height, not balloon.
      late double text;
      await pumpAt(tester, const Size(1080, 800), () => text = 14.rsp);

      expect(text, closeTo(14, 0.01),
          reason: 'minTextAdapt uses min(scaleWidth, scaleHeight)');
    });
  });

  group('on a smaller screen', () {
    testWidgets('sizes shrink rather than overflowing', (tester) async {
      late double chartHeight;
      await pumpAt(tester, const Size(320, 640), () => chartHeight = 230.rh);

      expect(chartHeight, lessThan(230),
          reason: 'a fixed chart height would crowd a small phone');
      // splitScreenMode floors the effective height at 700, so the shrink is
      // 700/800 rather than 640/800 — deliberately gentle.
      expect(chartHeight, closeTo(201.25, 0.5));
    });
  });
}
