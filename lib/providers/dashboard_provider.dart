import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/app_constants.dart';
import '../data/repositories/offline_transaction_repository.dart';
import 'sync_provider.dart';
import 'transaction_provider.dart';

class DashboardSummary {
  /// Income dated this month only.
  final double totalIncome;

  /// Expenses dated this month only.
  final double totalExpense;

  /// What was left over from every earlier month. Negative if earlier
  /// spending ran ahead of earlier income.
  final double carriedForward;

  /// Money available now: [carriedForward] + [totalIncome] − [totalExpense].
  final double balance;
  final Map<String, double> expenseByCategory;

  const DashboardSummary({
    required this.totalIncome,
    required this.totalExpense,
    required this.carriedForward,
    required this.balance,
    required this.expenseByCategory,
  });

  static const empty = DashboardSummary(
    totalIncome: 0,
    totalExpense: 0,
    carriedForward: 0,
    balance: 0,
    expenseByCategory: {},
  );
}

/// The dashboard numbers for the month containing [now].
///
/// Income and expense cover this month alone, but the balance does not reset
/// on the 1st: it opens with whatever earlier months left over. [now] is
/// injected so the month rollover can be tested without the wall clock.
DashboardSummary buildDashboardSummary(
  OfflineTransactionRepository repo, {
  required DateTime now,
}) {
  final start = DateTime(now.year, now.month, 1);
  final end = DateTime(now.year, now.month + 1, 0, 23, 59, 59);

  final sums = repo.sumByType(start: start, end: end);
  final breakdown = repo.categoryBreakdown(
    start: start,
    end: end,
    type: TransactionType.expense,
  );

  final income = sums[TransactionType.income] ?? 0;
  final expense = sums[TransactionType.expense] ?? 0;
  final carriedForward = repo.balanceBefore(start);

  return DashboardSummary(
    totalIncome: income,
    totalExpense: expense,
    carriedForward: carriedForward,
    balance: carriedForward + income - expense,
    expenseByCategory: breakdown,
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

  return buildDashboardSummary(
    ref.watch(offlineTransactionRepositoryProvider),
    now: DateTime.now(),
  );
});
