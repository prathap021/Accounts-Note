import 'package:flutter_test/flutter_test.dart';
import 'package:accounts_note/core/constants/app_constants.dart';
import 'package:accounts_note/data/local/sync_status.dart';
import 'package:accounts_note/features/dashboard/dashboard_screen.dart';
import 'package:accounts_note/models/transaction_model.dart';

/// The dashboard's "Last 7 days" bars.
void main() {
  var n = 0;
  TransactionModel tx(
    double amount,
    DateTime date, {
    TransactionType type = TransactionType.expense,
    String? card,
    bool deleted = false,
  }) => TransactionModel(
    id: 't${n++}',
    type: type,
    amount: amount,
    categoryId: 'food',
    categoryName: 'Food',
    date: date,
    creditCardId: card,
    createdAt: date,
    updatedAt: date,
    pendingOp: deleted ? PendingOp.delete : PendingOp.none,
  );

  final today = DateTime(2026, 11, 8, 15, 30);

  test('seven days ending today, oldest first, empty days at zero', () {
    final days = lastSevenDaysSpending([
      tx(450, DateTime(2026, 11, 8, 9)),
      tx(50, DateTime(2026, 11, 8, 21)),
      tx(320, DateTime(2026, 11, 6, 23, 50)),
    ], lastDay: today);

    expect(days.map((d) => d.day), [
      for (var d = 2; d <= 8; d++) DateTime(2026, 11, d),
    ]);
    expect(days.last.amount, 500, reason: 'every entry of the day adds up');
    expect(days[4].amount, 320);
    expect(days.first.amount, 0);
  });

  test('only cash spending counts, as elsewhere on the dashboard', () {
    final days = lastSevenDaysSpending([
      tx(100, DateTime(2026, 11, 8, 9)),
      tx(900, DateTime(2026, 11, 8, 9), type: TransactionType.income),
      tx(700, DateTime(2026, 11, 8, 9), card: 'hdfc'),
      tx(60, DateTime(2026, 11, 8, 9), deleted: true),
      // Outside the seven days.
      tx(999, DateTime(2026, 11, 1, 12)),
    ], lastDay: today);

    expect(days.last.amount, 100);
    expect(days.fold<double>(0, (s, d) => s + d.amount), 100);
  });

  test('the week can cross into the previous month', () {
    final days = lastSevenDaysSpending([
      tx(80, DateTime(2026, 10, 30, 10)),
    ], lastDay: DateTime(2026, 11, 2));

    expect(days.first.day, DateTime(2026, 10, 27));
    expect(days.firstWhere((d) => d.day == DateTime(2026, 10, 30)).amount, 80);
  });
}
