import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/app_constants.dart';
import 'auth_provider.dart';
import 'transaction_provider.dart';

class DashboardSummary {
  final double totalIncome;
  final double totalExpense;
  final double balance;
  final Map<String, double> expenseByCategory;

  const DashboardSummary({
    required this.totalIncome,
    required this.totalExpense,
    required this.balance,
    required this.expenseByCategory,
  });

  static const empty = DashboardSummary(
    totalIncome: 0,
    totalExpense: 0,
    balance: 0,
    expenseByCategory: {},
  );
}

/// One aggregate read for "this month" powering the dashboard cards and
/// the category-breakdown chart. Kept as a single FutureProvider (not a
/// stream) to avoid re-summing on every keystroke elsewhere; screens can
/// call `ref.invalidate(dashboardSummaryProvider)` after a transaction
/// write to refresh it, or pull-to-refresh.
final dashboardSummaryProvider = FutureProvider<DashboardSummary>((ref) async {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return DashboardSummary.empty;

  final now = DateTime.now();
  final start = DateTime(now.year, now.month, 1);
  final end = DateTime(now.year, now.month + 1, 0, 23, 59, 59);

  final repo = ref.watch(transactionRepositoryProvider);
  final sumsResult = await repo.sumByType(uid, start: start, end: end);
  final breakdownResult = await repo.categoryBreakdown(
    uid,
    start: start,
    end: end,
    type: TransactionType.expense,
  );

  final sums = sumsResult.when(success: (d) => d, failure: (_) => {});
  final breakdown = breakdownResult.when(success: (d) => d, failure: (_) => <String, double>{});

  final income = sums[TransactionType.income] ?? 0;
  final expense = sums[TransactionType.expense] ?? 0;

  return DashboardSummary(
    totalIncome: income,
    totalExpense: expense,
    balance: income - expense,
    expenseByCategory: breakdown,
  );
});
