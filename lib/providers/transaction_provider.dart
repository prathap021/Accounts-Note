import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/services/app_review_service.dart';
import '../data/repositories/offline_transaction_repository.dart';
import '../data/repositories/transaction_repository.dart';
import '../models/transaction_model.dart';
import 'auth_provider.dart';
import 'subscription_provider.dart';
import 'sync_provider.dart';

final transactionRepositoryProvider = Provider<TransactionRepository>((ref) {
  return TransactionRepository();
});

/// Holds the currently-applied filter for the Transactions screen. UI
/// widgets update this; watchTransactionsProvider reacts automatically.
class _TransactionFilterNotifier extends Notifier<TransactionFilter> {
  @override
  TransactionFilter build() => const TransactionFilter();

  void update(TransactionFilter filter) => state = filter;
}

final transactionFilterProvider =
    NotifierProvider<_TransactionFilterNotifier, TransactionFilter>(
  _TransactionFilterNotifier.new,
);

/// Every transaction, ignoring the Activity screen's filter.
///
/// The filter belongs to Activity alone. Anything else that shows totals or a
/// summary — the dashboard, budgets, reports — must not change because the
/// user narrowed a list on another tab.
final allTransactionsStreamProvider =
    StreamProvider<List<TransactionModel>>((ref) {
  final ready = ref.watch(localStoreReadyProvider).asData?.value ?? false;
  if (!ready) return Stream.value(const []);
  return ref.watch(offlineTransactionRepositoryProvider).watchTransactions();
});

/// Live list of transactions honouring the active filter, read from the local
/// Hive store so it is available on the first frame with no network.
///
/// Only the Activity screen should use this.
final transactionsStreamProvider = StreamProvider<List<TransactionModel>>((ref) {
  final ready = ref.watch(localStoreReadyProvider).asData?.value ?? false;
  if (!ready) return Stream.value(const []);
  final filter = ref.watch(transactionFilterProvider);
  return ref
      .watch(offlineTransactionRepositoryProvider)
      .watchTransactions(filter: filter);
});

/// Encapsulates add/edit/delete so screens don't call the repository
/// directly and so we get consistent loading/error state everywhere.
/// Writes go to Hive and return immediately — these never await the network,
/// so the form closes at local-write speed whether online or off.
class TransactionActionsNotifier extends Notifier<AsyncValue<void>> {
  late OfflineTransactionRepository _repo;
  String? _uid;

  @override
  AsyncValue<void> build() {
    _repo = ref.watch(offlineTransactionRepositoryProvider);
    _uid = ref.watch(currentUidProvider);
    return const AsyncData(null);
  }

  /// Refuses with [DailyLimitReached] as the error when today's allowance for
  /// the entry's type is used up, so the form can offer an upgrade.
  Future<bool> addTransaction(TransactionModel tx) async {
    if (_uid == null) return false;
    state = const AsyncLoading();
    final blocked = await ref.read(dailyLimitCheckerProvider).check(tx.type);
    if (blocked != null) {
      state = AsyncError(blocked, StackTrace.current);
      return false;
    }
    final result = await _repo.addTransaction(tx);
    return result.when(
      success: (_) {
        state = const AsyncData(null);
        AppReviewService.checkAndAskForReview();
        return true;
      },
      failure: (f) {
        state = AsyncError(f, StackTrace.current);
        return false;
      },
    );
  }

  Future<bool> updateTransaction(TransactionModel tx) async {
    if (_uid == null) return false;
    state = const AsyncLoading();
    final result = await _repo.updateTransaction(tx);
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

  Future<bool> deleteTransaction(String txId) async {
    if (_uid == null) return false;
    state = const AsyncLoading();
    final result = await _repo.deleteTransaction(txId);
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
}

final transactionActionsProvider =
    NotifierProvider<TransactionActionsNotifier, AsyncValue<void>>(
  TransactionActionsNotifier.new,
);
