import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/constants/app_constants.dart';
import '../../models/transaction_model.dart';

/// One category's total in a report period.
class CategoryTotal {
  const CategoryTotal({
    required this.categoryId,
    required this.name,
    required this.amount,
    required this.count,
    required this.share,
  });

  final String categoryId;
  final String name;
  final double amount;
  final int count;

  /// Fraction of the period's total for this type, 0–1.
  final double share;
}

/// How finely the trend chart groups the period.
enum TrendBucket { day, week, month }

/// Income and spending in one slice of the period.
class TrendPoint {
  const TrendPoint({
    required this.start,
    required this.label,
    this.income = 0,
    this.expense = 0,
  });

  final DateTime start;
  final String label;
  final double income;
  final double expense;

  TrendPoint add(TransactionModel t) => TrendPoint(
    start: start,
    label: label,
    income: income + (t.type == TransactionType.income ? t.amount : 0),
    expense: expense + (t.type == TransactionType.expense ? t.amount : 0),
  );
}

/// Where the money went in a report period, and how it moved over time.
///
/// Counts the same entries as the report's totals (card charges included),
/// so the categories always add up to the Expenses figure above them.
class ReportInsights {
  const ReportInsights({
    required this.spending,
    required this.earning,
    required this.bucket,
    required this.trend,
  });

  /// Expense categories, largest first.
  final List<CategoryTotal> spending;

  /// Income categories, largest first.
  final List<CategoryTotal> earning;
  final TrendBucket bucket;

  /// Every slice of the period in order, empty ones included. Empty when the
  /// period is a single day, where a trend says nothing.
  final List<TrendPoint> trend;

  static TrendBucket bucketFor(DateTimeRange range) {
    final days = range.end.difference(range.start).inDays + 1;
    if (days <= 31) return TrendBucket.day;
    if (days <= 183) return TrendBucket.week;
    return TrendBucket.month;
  }

  static DateTime _bucketStart(DateTime d, TrendBucket b) => switch (b) {
    TrendBucket.day => DateTime(d.year, d.month, d.day),
    // Weeks start on Monday, as the Week report does.
    TrendBucket.week => DateTime(d.year, d.month, d.day - (d.weekday - 1)),
    TrendBucket.month => DateTime(d.year, d.month),
  };

  static DateTime _next(DateTime d, TrendBucket b) => switch (b) {
    TrendBucket.day => DateTime(d.year, d.month, d.day + 1),
    TrendBucket.week => DateTime(d.year, d.month, d.day + 7),
    TrendBucket.month => DateTime(d.year, d.month + 1),
  };

  static String _label(DateTime d, TrendBucket b) => switch (b) {
    TrendBucket.day => DateFormat('d MMM').format(d),
    TrendBucket.week => DateFormat('d MMM').format(d),
    TrendBucket.month => DateFormat('MMM yy').format(d),
  };

  static List<CategoryTotal> _byCategory(
    Iterable<TransactionModel> entries,
    TransactionType type,
  ) {
    final amounts = <String, double>{};
    final counts = <String, int>{};
    final names = <String, String>{};
    var total = 0.0;
    for (final t in entries) {
      if (t.type != type) continue;
      amounts[t.categoryId] = (amounts[t.categoryId] ?? 0) + t.amount;
      counts[t.categoryId] = (counts[t.categoryId] ?? 0) + 1;
      names[t.categoryId] = t.categoryName;
      total += t.amount;
    }
    final list = [
      for (final id in amounts.keys)
        CategoryTotal(
          categoryId: id,
          name: names[id]!,
          amount: amounts[id]!,
          count: counts[id]!,
          share: total == 0 ? 0 : amounts[id]! / total,
        ),
    ]..sort((a, b) => b.amount.compareTo(a.amount));
    return list;
  }

  factory ReportInsights.build(
    Iterable<TransactionModel> all,
    DateTimeRange range,
  ) {
    final inRange = [
      for (final t in all)
        if (!t.isDeleted &&
            !t.date.isBefore(range.start) &&
            !t.date.isAfter(range.end))
          t,
    ];
    final bucket = bucketFor(range);
    final singleDay =
        DateUtils.isSameDay(range.start, range.end) ||
        range.end.difference(range.start) < const Duration(days: 1);

    final trend = <TrendPoint>[];
    if (!singleDay) {
      final index = <DateTime, int>{};
      for (
        var d = _bucketStart(range.start, bucket);
        !d.isAfter(range.end);
        d = _next(d, bucket)
      ) {
        index[d] = trend.length;
        trend.add(TrendPoint(start: d, label: _label(d, bucket)));
      }
      for (final t in inRange) {
        final i = index[_bucketStart(t.date, bucket)];
        if (i != null) trend[i] = trend[i].add(t);
      }
    }

    return ReportInsights(
      spending: _byCategory(inRange, TransactionType.expense),
      earning: _byCategory(inRange, TransactionType.income),
      bucket: bucket,
      trend: trend,
    );
  }
}
