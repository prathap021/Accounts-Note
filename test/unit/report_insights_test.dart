import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:accounts_note/core/constants/app_constants.dart';
import 'package:accounts_note/data/local/sync_status.dart';
import 'package:accounts_note/features/reports/report_insights.dart';
import 'package:accounts_note/features/reports/reports_screen.dart';
import 'package:accounts_note/models/transaction_model.dart';

void main() {
  var n = 0;
  TransactionModel tx(
    TransactionType type,
    double amount,
    String category,
    DateTime date, {
    bool deleted = false,
    String? card,
  }) => TransactionModel(
    id: 't${n++}',
    type: type,
    amount: amount,
    categoryId: category.toLowerCase(),
    categoryName: category,
    date: date,
    creditCardId: card,
    createdAt: date,
    updatedAt: date,
    pendingOp: deleted ? PendingOp.delete : PendingOp.none,
  );

  final nov = DateTimeRange(
    start: DateTime(2026, 11, 1),
    end: DateTime(2026, 11, 30, 23, 59, 59),
  );

  test('categories add up to the expenses, largest first', () {
    final insights = ReportInsights.build([
      tx(TransactionType.expense, 300, 'Food', DateTime(2026, 11, 2)),
      tx(TransactionType.expense, 200, 'Food', DateTime(2026, 11, 5)),
      tx(TransactionType.expense, 1500, 'Rent', DateTime(2026, 11, 1)),
      // On a card: still spending, as in the report's totals.
      tx(
        TransactionType.expense,
        500,
        'Shopping',
        DateTime(2026, 11, 3),
        card: 'hdfc',
      ),
      tx(TransactionType.income, 50000, 'Salary', DateTime(2026, 11, 1)),
      // Outside the period, or deleted: left out.
      tx(TransactionType.expense, 999, 'Food', DateTime(2026, 10, 31)),
      tx(
        TransactionType.expense,
        999,
        'Food',
        DateTime(2026, 11, 9),
        deleted: true,
      ),
    ], nov);

    expect(insights.spending.map((c) => c.name), ['Rent', 'Food', 'Shopping']);
    final food = insights.spending[1];
    expect(food.amount, 500);
    expect(food.count, 2);
    expect(food.share, closeTo(500 / 2500, 1e-9));
    expect(insights.spending.fold<double>(0, (s, c) => s + c.amount), 2500);
    expect(insights.earning.single.name, 'Salary');
  });

  test('a month trends day by day, with empty days kept', () {
    final insights = ReportInsights.build([
      tx(TransactionType.expense, 100, 'Food', DateTime(2026, 11, 2, 9)),
      tx(TransactionType.expense, 50, 'Food', DateTime(2026, 11, 2, 20)),
      tx(TransactionType.income, 700, 'Gift', DateTime(2026, 11, 30, 23)),
    ], nov);
    expect(insights.bucket, TrendBucket.day);
    expect(insights.trend, hasLength(30));
    expect(insights.trend[1].expense, 150);
    expect(insights.trend[0].expense, 0);
    expect(insights.trend.last.income, 700);
  });

  test('longer periods group by week, then by month', () {
    final quarter = DateTimeRange(
      start: DateTime(2026, 9, 1),
      end: DateTime(2026, 11, 30),
    );
    expect(ReportInsights.bucketFor(quarter), TrendBucket.week);
    final year = DateTimeRange(
      start: DateTime(2026, 1, 1),
      end: DateTime(2026, 12, 31),
    );
    final insights = ReportInsights.build([
      tx(TransactionType.expense, 10, 'Food', DateTime(2026, 3, 15)),
    ], year);
    expect(insights.bucket, TrendBucket.month);
    expect(insights.trend, hasLength(12));
    expect(insights.trend[2].expense, 10);
  });

  test('a single day has no trend', () {
    final now = DateTime(2026, 11, 7, 15);
    final range = const ReportPeriod(ReportRange.day).resolve(now);
    expect(range.start, DateTime(2026, 11, 7));
    expect(range.end, now);
    final insights = ReportInsights.build([
      tx(TransactionType.expense, 80, 'Food', DateTime(2026, 11, 7, 9)),
      tx(TransactionType.expense, 80, 'Food', DateTime(2026, 11, 6, 9)),
    ], range);
    expect(insights.trend, isEmpty);
    expect(insights.spending.single.amount, 80);
  });
}
