import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/app_constants.dart';
import '../data/repositories/offline_transaction_repository.dart';
import 'sync_provider.dart';
import 'transaction_provider.dart';

class DashboardSummary {
  /// Income dated this month only.
  final double totalIncome;

  /// Cash expenses dated this month only.
  ///
  /// Excludes anything charged to a credit card: that is debt, not money
  /// leaving the user's pocket, and it is reported under [creditCardSpend].
  final double totalExpense;

  /// Charged to credit cards this month. Shown in its own section rather
  /// than netted against cash, so neither number misleads.
  final double creditCardSpend;

  /// What was left over from every earlier month. Negative if earlier
  /// spending ran ahead of earlier income.
  final double carriedForward;

  /// Money available now: [carriedForward] + [totalIncome] − [totalExpense].
  final double balance;
  final Map<String, double> expenseByCategory;

  const DashboardSummary({
    required this.totalIncome,
    required this.totalExpense,
    required this.creditCardSpend,
    required this.carriedForward,
    required this.balance,
    required this.expenseByCategory,
  });

  static const empty = DashboardSummary(
    totalIncome: 0,
    totalExpense: 0,
    creditCardSpend: 0,
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
///
/// Every figure here is cash. Credit-card charges are deliberately kept out
/// of the balance, the expense total, the carry-forward and the category
/// breakdown: the card issuer has paid the merchant, so the user's own money
/// has not moved. Card spend is reported separately as [creditCardSpend] and
/// broken down per card on the dashboard.
DashboardSummary buildDashboardSummary(
  OfflineTransactionRepository repo, {
  required DateTime now,
}) {
  final start = DateTime(now.year, now.month, 1);
  final end = DateTime(now.year, now.month + 1, 0, 23, 59, 59);

  final sums = repo.sumByType(start: start, end: end, cashOnly: true);
  final breakdown = repo.categoryBreakdown(
    start: start,
    end: end,
    type: TransactionType.expense,
    cashOnly: true,
  );

  final income = sums[TransactionType.income] ?? 0;
  final expense = sums[TransactionType.expense] ?? 0;
  final carriedForward = repo.balanceBefore(start, cashOnly: true);

  return DashboardSummary(
    totalIncome: income,
    totalExpense: expense,
    creditCardSpend: repo.creditCardSpend(start: start, end: end),
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
