import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:income_expense_tracker/core/theme/app_theme.dart';
import 'package:income_expense_tracker/widgets/credit_card_usage.dart';

import '../support/fixtures.dart';

/// The card tile reports debt, not cash, so its wording has to stand on its
/// own: "left" and "over the limit" are the only cues that this money was
/// never in the user's balance.
void main() {
  Future<void> pumpTile(
    WidgetTester tester, {
    double? limit,
    required double spent,
  }) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: CreditCardUsageTile(
          card: creditCardFixture(name: 'HDFC Millennia', creditLimit: limit),
          spent: spent,
          currency: 'INR',
        ),
      ),
    ));
    await tester.pump();
  }

  group('creditCardUtilisation', () {
    test('is the plain ratio under the limit', () {
      expect(creditCardUtilisation(2500, 10000), 0.25);
    });

    test('clamps at full rather than overflowing the bar', () {
      expect(creditCardUtilisation(30000, 10000), 1.0);
    });

    test('is null without a usable limit', () {
      expect(creditCardUtilisation(500, null), isNull);
      expect(creditCardUtilisation(500, 0), isNull);
      // A negative limit is not a limit; treat it as unset rather than
      // producing a negative bar.
      expect(creditCardUtilisation(500, -100), isNull);
    });

    test('is zero when nothing has been spent', () {
      expect(creditCardUtilisation(0, 10000), 0.0);
    });
  });

  group('with a limit', () {
    testWidgets('shows the spend, the limit and the headroom left',
        (tester) async {
      await pumpTile(tester, limit: 50000, spent: 12000);

      expect(find.textContaining('12,000'), findsOneWidget);
      expect(find.textContaining('50,000'), findsOneWidget);
      expect(find.textContaining('left'), findsOneWidget);
      expect(find.textContaining('38,000'), findsOneWidget);
    });

    testWidgets('draws the bar at the right fraction', (tester) async {
      await pumpTile(tester, limit: 50000, spent: 12500);

      final bar = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(bar.value, 0.25);
    });

    testWidgets('says how far over the limit, not just "full"',
        (tester) async {
      // The bar pins at 100% here, so the words carry the overspend.
      await pumpTile(tester, limit: 10000, spent: 13000);

      // Anchored to the overspend figure, not a bare "3,000": the spend
      // itself renders as 13,000 and would match a looser pattern.
      expect(find.textContaining('3,000.00 over the limit'), findsOneWidget);
      expect(find.textContaining('left'), findsNothing);
    });

    testWidgets('exactly at the limit is not over it', (tester) async {
      await pumpTile(tester, limit: 10000, spent: 10000);

      expect(find.textContaining('over the limit'), findsNothing);
      expect(find.textContaining('left'), findsOneWidget);
    });
  });

  group('without a limit', () {
    testWidgets('shows the spend and says no limit is set', (tester) async {
      await pumpTile(tester, limit: null, spent: 4200);

      expect(find.text('No limit set'), findsOneWidget);
      expect(find.textContaining('4,200'), findsOneWidget);
    });

    testWidgets('omits the bar entirely rather than drawing an empty one',
        (tester) async {
      await pumpTile(tester, limit: null, spent: 4200);
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });
  });

  testWidgets('identifies the card by name and last four', (tester) async {
    await pumpTile(tester, limit: 50000, spent: 1000);
    expect(find.textContaining('HDFC Millennia'), findsOneWidget);
    expect(find.textContaining('4321'), findsOneWidget);
  });
}
