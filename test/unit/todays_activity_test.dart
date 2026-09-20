import 'package:flutter_test/flutter_test.dart';
import 'package:income_expense_tracker/core/constants/app_constants.dart';
import 'package:income_expense_tracker/features/dashboard/dashboard_screen.dart';

import '../support/fixtures.dart';

/// The dashboard lists today's entries only. The day boundary is the part
/// that quietly breaks — a transaction at 00:01 or 23:59 must land on the
/// right side of it.
void main() {
  final now = DateTime(2026, 9, 20, 14, 30);

  test('an empty ledger yields nothing', () {
    expect(todaysActivity(const [], now: now), isEmpty);
  });

  test('keeps entries from today', () {
    final items = todaysActivity([
      txFixture(id: 'a', date: DateTime(2026, 9, 20, 9)),
      txFixture(id: 'b', date: DateTime(2026, 9, 20, 13)),
    ], now: now);

    expect(items.map((t) => t.id), ['a', 'b']);
  });

  test('drops yesterday and earlier', () {
    final items = todaysActivity([
      txFixture(id: 'today', date: DateTime(2026, 9, 20, 9)),
      txFixture(id: 'yesterday', date: DateTime(2026, 9, 19, 23, 59)),
      txFixture(id: 'lastMonth', date: DateTime(2026, 8, 20, 9)),
    ], now: now);

    expect(items.map((t) => t.id), ['today']);
  });

  group('day boundary', () {
    test('midnight today is included', () {
      final items = todaysActivity([
        txFixture(id: 'midnight', date: DateTime(2026, 9, 20)),
      ], now: now);
      expect(items, hasLength(1));
    });

    test('one minute before midnight is excluded', () {
      final items = todaysActivity([
        txFixture(id: 'justBefore', date: DateTime(2026, 9, 19, 23, 59, 59)),
      ], now: now);
      expect(items, isEmpty, reason: 'that belongs to yesterday');
    });

    test('later today is kept, even past the current time', () {
      // A transaction can be dated ahead within the same day.
      final items = todaysActivity([
        txFixture(id: 'tonight', date: DateTime(2026, 9, 20, 23, 30)),
      ], now: now);
      expect(items, hasLength(1));
    });
  });

  test('caps the list so the dashboard stays short', () {
    final many = List.generate(
      12,
      (i) => txFixture(id: 'tx$i', date: DateTime(2026, 9, 20, 8 + i % 10)),
    );

    expect(todaysActivity(many, now: now), hasLength(5));
    expect(todaysActivity(many, now: now, limit: 3), hasLength(3));
  });

  test('preserves the order it was given', () {
    final items = todaysActivity([
      txFixture(id: 'newest', date: DateTime(2026, 9, 20, 18)),
      txFixture(id: 'middle', date: DateTime(2026, 9, 20, 12)),
      txFixture(id: 'oldest', date: DateTime(2026, 9, 20, 6)),
    ], now: now);

    expect(items.map((t) => t.id), ['newest', 'middle', 'oldest'],
        reason: 'the store already sorts newest first');
  });

  test('income and expenses both appear', () {
    final items = todaysActivity([
      txFixture(id: 'in', type: TransactionType.income,
          date: DateTime(2026, 9, 20, 10)),
      txFixture(id: 'out', date: DateTime(2026, 9, 20, 11)),
    ], now: now);

    expect(items, hasLength(2));
  });
}
