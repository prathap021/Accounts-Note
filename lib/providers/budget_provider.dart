import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../data/repositories/budget_repository.dart';
import '../models/budget_model.dart';
import 'auth_provider.dart';
import 'transaction_provider.dart';

final budgetRepositoryProvider = Provider<BudgetRepository>((ref) {
  return BudgetRepository();
});

/// Current financial-month period key, e.g. "2026-09".
final currentPeriodProvider = Provider<String>((ref) {
  return DateFormat('yyyy-MM').format(DateTime.now());
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
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return {};
  final now = DateTime.now();
  final start = DateTime(now.year, now.month, 1);
  final end = DateTime(now.year, now.month + 1, 0, 23, 59, 59);
  final result = await ref
      .watch(transactionRepositoryProvider)
      .categoryBreakdown(uid, start: start, end: end);
  return result.when(success: (data) => data, failure: (_) => {});
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
