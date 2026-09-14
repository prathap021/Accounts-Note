import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/services/app_review_service.dart';
import '../data/repositories/transaction_repository.dart';
import '../models/transaction_model.dart';
import 'auth_provider.dart';

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

/// Real-time list of transactions honoring the active filter. Rebuilds
/// automatically on login/logout because it depends on currentUidProvider.
final transactionsStreamProvider = StreamProvider<List<TransactionModel>>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return Stream.value(const []);
  final filter = ref.watch(transactionFilterProvider);
  return ref.watch(transactionRepositoryProvider).watchTransactions(uid, filter: filter);
});

/// Encapsulates add/edit/delete so screens don't call the repository
/// directly and so we get consistent loading/error state everywhere.
class TransactionActionsNotifier extends Notifier<AsyncValue<void>> {
  late TransactionRepository _repo;
  String? _uid;

  @override
  AsyncValue<void> build() {
    _repo = ref.watch(transactionRepositoryProvider);
    _uid = ref.watch(currentUidProvider);
    return const AsyncData(null);
  }

  Future<bool> addTransaction(TransactionModel tx) async {
    if (_uid == null) return false;
    state = const AsyncLoading();
    final result = await _repo.addTransaction(_uid!, tx);
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
    final result = await _repo.updateTransaction(_uid!, tx);
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
    final result = await _repo.deleteTransaction(_uid!, txId);
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
