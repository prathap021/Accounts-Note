import 'package:equatable/equatable.dart';

import '../core/constants/app_constants.dart';

/// How many income and expense entries were added on one day.
///
/// Days are the user's own calendar days: the counter that limits them is
/// keyed by the local date the entry was created on (see [usageDayOf]), so the
/// allowance resets at the user's midnight, not the server's.
class DailyUsage extends Equatable {
  /// `yyyy-MM-dd`.
  final String day;
  final int income;
  final int expense;

  const DailyUsage({required this.day, this.income = 0, this.expense = 0});

  /// Every entry, whichever type: what the daily limit counts.
  int get total => income + expense;

  int countFor(TransactionType type) => switch (type) {
    TransactionType.income => income,
    TransactionType.expense => expense,
  };

  DailyUsage operator +(DailyUsage other) => DailyUsage(
    day: day,
    income: income + other.income,
    expense: expense + other.expense,
  );

  factory DailyUsage.fromMap(String day, Map<String, dynamic>? data) =>
      DailyUsage(
        day: day,
        income: (data?['income'] as num?)?.toInt() ?? 0,
        expense: (data?['expense'] as num?)?.toInt() ?? 0,
      );

  @override
  List<Object?> get props => [day, income, expense];
}

/// The local calendar day (`yyyy-MM-dd`) an entry created at [createdAt] counts
/// against, for a device [tzOffsetMinutes] ahead of UTC.
///
/// The security rules compute the same thing from the entry's `createdAt` and
/// `createdTzOffsetMinutes`, and refuse the write unless it matches the
/// counter being bumped. Keep the two in step.
String usageDayOf(DateTime createdAt, int tzOffsetMinutes) {
  final local = createdAt.toUtc().add(Duration(minutes: tzOffsetMinutes));
  return dayKey(local);
}

/// `yyyy-MM-dd` for the calendar fields of [d], as they are.
String dayKey(DateTime d) {
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '${d.year}-$m-$day';
}

/// Today on this device.
String todayKey([DateTime? now]) => dayKey(now ?? DateTime.now());
