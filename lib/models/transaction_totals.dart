import '../core/constants/app_constants.dart';
import 'transaction_model.dart';

/// Money in, money out and how many entries — the summary shown for whatever
/// the user has filtered Activity down to.
class TransactionTotals {
  final double income;
  final double expense;
  final int count;

  const TransactionTotals({
    required this.income,
    required this.expense,
    required this.count,
  });

  static const empty = TransactionTotals(income: 0, expense: 0, count: 0);

  factory TransactionTotals.of(Iterable<TransactionModel> items) {
    double income = 0, expense = 0;
    var count = 0;
    for (final t in items) {
      if (t.type == TransactionType.income) {
        income += t.amount;
      } else {
        expense += t.amount;
      }
      count++;
    }
    return TransactionTotals(income: income, expense: expense, count: count);
  }

  /// Positive when more came in than went out.
  double get net => income - expense;

  bool get isEmpty => count == 0;
}
