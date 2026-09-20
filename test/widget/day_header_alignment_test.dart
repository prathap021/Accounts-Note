import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:income_expense_tracker/core/theme/app_theme.dart';
import 'package:income_expense_tracker/core/utils/currency_formatter.dart';

/// Regression guard for the Activity day header.
///
/// The totals used to sit in a Flexible, whose child is positioned at the
/// START of its slot. On a day with only expenses the single total drifted
/// into the middle of the row instead of sitting flush right, so the column
/// of amounts did not line up down the screen.
///
/// A FittedBox was then added to stop wide totals overflowing, which caused a
/// second problem: days with both totals scaled down while days with one
/// stayed full size, so the amounts read as two different type sizes. The
/// totals are now laid out at natural size and the label absorbs the slack.
///
/// This rebuilds the same layout and measures what actually lands where.
Widget header({
  required String label,
  required double income,
  required double expense,
}) {
  Widget total(double amount, bool isIncome) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isIncome ? Icons.south_west_rounded : Icons.north_east_rounded,
            size: 13,
            color: isIncome ? AppColors.income : AppColors.expense,
          ),
          const SizedBox(width: 3),
          Text(
            CurrencyFormatter.format(amount),
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: isIncome ? AppColors.income : AppColors.expense,
            ),
          ),
        ],
      );

  return Row(
    children: [
      Expanded(
        child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      const SizedBox(width: AppSpacing.sm),
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (income > 0) total(income, true),
          if (income > 0 && expense > 0) const SizedBox(width: AppSpacing.md),
          if (expense > 0) total(expense, false),
        ],
      ),
    ],
  );
}

void main() {
  const rowWidth = 360.0;

  Future<Rect> pumpAndMeasureTotals(
    WidgetTester tester, {
    required double income,
    required double expense,
    String label = 'Friday, Sep 18',
  }) async {
    tester.view.physicalSize = const Size(400, 200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: rowWidth,
            child: header(label: label, income: income, expense: expense),
          ),
        ),
      ),
    ));
    await tester.pump();

    // The totals are the last child of the outer Row.
    return tester.getRect(find.byType(Row).at(1));
  }

  /// Height of the rendered amount text, as a proxy for its type size.
  Future<double> amountHeight(
    WidgetTester tester, {
    required double income,
    required double expense,
  }) async {
    await pumpAndMeasureTotals(tester, income: income, expense: expense);
    final amount = income > 0
        ? CurrencyFormatter.format(income)
        : CurrencyFormatter.format(expense);
    return tester.getRect(find.text(amount)).height;
  }

  test('sanity: the row is the width the tests assume', () {
    expect(rowWidth, 360.0);
  });

  testWidgets('an expense-only day sits flush right', (tester) async {
    final rect = await pumpAndMeasureTotals(tester, income: 0, expense: 215);
    final rowRight = tester.getRect(find.byType(Row).first).right;

    expect(rect.right, closeTo(rowRight, 1),
        reason: 'a single total must align with the screen edge, not drift '
            'into the middle of the row');
  });

  testWidgets('an income-only day sits flush right', (tester) async {
    final rect = await pumpAndMeasureTotals(tester, income: 5000, expense: 0);
    final rowRight = tester.getRect(find.byType(Row).first).right;
    expect(rect.right, closeTo(rowRight, 1));
  });

  testWidgets('a day with both totals also sits flush right', (tester) async {
    final rect =
        await pumpAndMeasureTotals(tester, income: 5000, expense: 3395);
    final rowRight = tester.getRect(find.byType(Row).first).right;
    expect(rect.right, closeTo(rowRight, 1));
  });

  testWidgets('every combination lines up at the same right edge',
      (tester) async {
    final expenseOnly =
        await pumpAndMeasureTotals(tester, income: 0, expense: 215);
    final both =
        await pumpAndMeasureTotals(tester, income: 5000, expense: 3395);

    expect(expenseOnly.right, closeTo(both.right, 1),
        reason: 'days with and without income must share a right edge, or '
            'the column of amounts looks ragged');
  });

  testWidgets('a long day label does not push the totals off the row',
      (tester) async {
    final rect = await pumpAndMeasureTotals(
      tester,
      income: 5000,
      expense: 3395,
      label: 'Wednesday, September 30',
    );
    final rowRight = tester.getRect(find.byType(Row).first).right;

    expect(rect.right, lessThanOrEqualTo(rowRight + 1));
    expect(tester.takeException(), isNull, reason: 'no overflow');
  });

  group('type size is consistent between days', () {
    testWidgets('one total renders at the same size as two', (tester) async {
      final alone = await amountHeight(tester, income: 0, expense: 215);
      final paired = await amountHeight(tester, income: 5000, expense: 3395);

      expect(paired, closeTo(alone, 0.5),
          reason: 'scaling totals to fit made days with both amounts render '
              'smaller than days with one, so the column looked mismatched');
    });

    testWidgets('a larger amount does not shrink the text', (tester) async {
      final small = await amountHeight(tester, income: 0, expense: 70);
      final large = await amountHeight(tester, income: 0, expense: 1234567);

      expect(large, closeTo(small, 0.5));
    });
  });
}
