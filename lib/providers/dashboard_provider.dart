import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/app_constants.dart';
import 'sync_provider.dart';
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
/// Computed over the local Hive store and recomputed whenever it changes, so
/// the dashboard is correct offline and updates the instant a transaction is
/// saved — no cloud round-trip in the path.
final dashboardSummaryProvider = Provider<DashboardSummary>((ref) {
  // Depend on the local list so this recomputes on every local write.
  final ready = ref.watch(localStoreReadyProvider).asData?.value ?? false;
  final transactions =
      ref.watch(allTransactionsStreamProvider).asData?.value ?? const [];
  if (!ready && transactions.isEmpty) return DashboardSummary.empty;

  final now = DateTime.now();
  final start = DateTime(now.year, now.month, 1);
  final end = DateTime(now.year, now.month + 1, 0, 23, 59, 59);

  final repo = ref.watch(offlineTransactionRepositoryProvider);
  final sums = repo.sumByType(start: start, end: end);
  final breakdown = repo.categoryBreakdown(
    start: start,
    end: end,
    type: TransactionType.expense,
  );

  final income = sums[TransactionType.income] ?? 0;
  final expense = sums[TransactionType.expense] ?? 0;

  return DashboardSummary(
    totalIncome: income,
    totalExpense: expense,
    balance: income - expense,
    expenseByCategory: breakdown,
  );
});
