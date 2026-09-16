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
            child: AppLogo(size: size, rounded: false),
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
}
