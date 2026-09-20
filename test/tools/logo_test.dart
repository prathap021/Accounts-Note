@Tags(['tools'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:income_expense_tracker/widgets/app_logo.dart';

/// Regenerates assets/branding/app_icon_generated.png from [AppLogo].
///
/// This is a build tool, not a regression test: it compares the rendered
/// logo against the committed PNG and only passes right after a
/// regeneration. Tagged `tools` so it is skipped by default.
void main() {
  testWidgets('Generate App Logo PNG', (WidgetTester tester) async {
    const double size = 1024.0;
    tester.view.physicalSize = const Size(size, size);
    tester.view.devicePixelRatio = 1.0;

    await tester.pumpWidget(
      const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Center(
            // Flat, unrounded: the platforms apply their own mask, and the
            // adaptive-icon foreground must not carry a baked-in shadow.
            child: AppLogo(
              size: size,
              rounded: false,
              flat: true,
              safeZone: true,
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    await expectLater(
      find.byType(AppLogo),
      matchesGoldenFile('../../assets/branding/app_icon_generated.png'),
    );
  });


  testWidgets('Generate Android 12 splash icon', (WidgetTester tester) async {
    const double size = 1024.0;
    tester.view.physicalSize = const Size(size, size);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // Transparent background and a small mark: the Android 12 splash masks
    // whatever image it is given to a circle and draws its own background, so
    // the foreground needs room to breathe inside that mask.
    await tester.pumpWidget(
      const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: ColoredBox(
          color: Color(0x00000000),
          child: Center(
            child: AppLogoMark(size: size, contentScale: 0.42),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(AppLogoMark),
      matchesGoldenFile('../../assets/branding/app_splash_icon.png'),
    );
  });


  testWidgets('Generate Android adaptive-icon foreground',
      (WidgetTester tester) async {
    const double size = 1024.0;
    tester.view.physicalSize = const Size(size, size);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // Transparent: the adaptive background colour is supplied separately, and
    // Android masks the foreground to the device's icon shape. Handing it a
    // full tile means the tile's own background hides the adaptive colour and
    // the mark gets clipped at the mask edge.
    await tester.pumpWidget(
      const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Center(
          child: AppLogoMark(size: size, contentScale: 0.55),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(AppLogoMark),
      matchesGoldenFile('../../assets/branding/app_adaptive_foreground.png'),
    );
  });
}
