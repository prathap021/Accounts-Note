import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories/budget_repository.dart';
import '../models/budget_model.dart';
import 'auth_provider.dart';
import 'period_provider.dart';
import 'sync_provider.dart';
import 'transaction_provider.dart';

final budgetRepositoryProvider = Provider<BudgetRepository>((ref) {
  return BudgetRepository();
});

/// Current financial-month period key, e.g. "2026-09".
/// Budgets are saved per budgeting month (see [MoneyMonth.key]).
final currentPeriodProvider = Provider<String>((ref) {
  return ref.watch(currentMoneyMonthProvider).key;
});

final budgetsStreamProvider = StreamProvider<List<BudgetModel>>((ref) {
  final uid = ref.watch(currentUidProvider);
  final period = ref.watch(currentPeriodProvider);
  if (uid == null) return Stream.value(const []);
  return ref.watch(budgetRepositoryProvider).watchBudgets(uid, period);
});

/// Combines budgets with actual spend-per-category for this period so the
/// Budgets screen can render progress bars without duplicating math.
final budgetProgressProvider = FutureProvider<Map<String, double>>((ref) async {
  // Computed from Hive, so budgets track correctly with no network and
  // update the moment a transaction is saved.
  ref.watch(allTransactionsStreamProvider);
  final month = ref.watch(currentMoneyMonthProvider);
  return ref
      .watch(offlineTransactionRepositoryProvider)
      .categoryBreakdown(start: month.start, end: month.end);
});

class BudgetActionsNotifier extends Notifier<AsyncValue<void>> {
  late BudgetRepository _repo;
  String? _uid;

  @override
  AsyncValue<void> build() {
    _repo = ref.watch(budgetRepositoryProvider);
    _uid = ref.watch(currentUidProvider);
    return const AsyncData(null);
  }

  Future<bool> setBudget(BudgetModel budget) async {
    if (_uid == null) return false;
    state = const AsyncLoading();
    final result = await _repo.setBudget(_uid!, budget);
    return result.when(
      success: (_) {
        state = const AsyncData(null);
        return true;
      },
      failure: (f) {
        state = AsyncError(f, StackTrace.current);
        return false;
      },
    );
  }

  Future<bool> deleteBudget(String id) async {
    if (_uid == null) return false;
    final result = await _repo.deleteBudget(_uid!, id);
    return result.isSuccess;
  }
}

final budgetActionsProvider =
    NotifierProvider<BudgetActionsNotifier, AsyncValue<void>>(
  BudgetActionsNotifier.new,
);
