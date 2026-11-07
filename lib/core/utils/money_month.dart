import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

/// A budgeting month. It starts on [startDay] (1–28), so someone paid on the
/// 25th can run their month from the 25th to the 24th; with the default of 1
/// it is the calendar month.
@immutable
class MoneyMonth {
  /// Midnight on the first day.
  final DateTime start;

  /// The last moment of the last day.
  final DateTime end;
  final int startDay;

  const MoneyMonth._(this.start, this.end, this.startDay);

  static int clampDay(int day) => day < 1 ? 1 : (day > 28 ? 28 : day);

  /// The month that [date] falls in.
  factory MoneyMonth.containing(DateTime date, [int startDay = 1]) {
    final d = clampDay(startDay);
    final start = date.day >= d
        ? DateTime(date.year, date.month, d)
        : DateTime(date.year, date.month - 1, d);
    // DateTime rolls month 13 into January, so this works across years.
    final next = DateTime(start.year, start.month + 1, d);
    return MoneyMonth._(
      start,
      next.subtract(const Duration(milliseconds: 1)),
      d,
    );
  }

  MoneyMonth previous() =>
      MoneyMonth.containing(start.subtract(const Duration(days: 1)), startDay);

  MoneyMonth next() =>
      MoneyMonth.containing(end.add(const Duration(days: 1)), startDay);

  bool contains(DateTime t) => !t.isBefore(start) && !t.isAfter(end);

  /// The key budgets are saved under: the month the cycle starts in.
  String get key => DateFormat('yyyy-MM').format(start);

  /// "November 2026", or "25 Oct – 24 Nov 2026" for a custom start day.
  String get label {
    if (startDay == 1) return DateFormat('MMMM yyyy').format(start);
    final sameYear = start.year == end.year;
    return '${DateFormat(sameYear ? 'd MMM' : 'd MMM yyyy').format(start)} – '
        '${DateFormat('d MMM yyyy').format(end)}';
  }

  @override
  bool operator ==(Object other) =>
      other is MoneyMonth && other.start == start && other.startDay == startDay;

  @override
  int get hashCode => Object.hash(start, startDay);
}
