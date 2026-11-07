import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/app_constants.dart';
import '../core/utils/result.dart';
import '../data/repositories/account_repository.dart';
import '../models/account_model.dart';
import '../models/transaction_model.dart';
import 'auth_provider.dart';
import 'settings_provider.dart';
import 'transaction_provider.dart';

final accountRepositoryProvider = Provider<AccountRepository>(
  (ref) => AccountRepository(),
);

final accountsStreamProvider = StreamProvider<List<AccountModel>>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return Stream.value(const []);
  return ref.watch(accountRepositoryProvider).watchAccounts(uid);
});

final transfersStreamProvider = StreamProvider<List<TransferModel>>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return Stream.value(const []);
  return ref.watch(accountRepositoryProvider).watchTransfers(uid);
});

final accountLookupProvider = Provider<Map<String, AccountModel>>((ref) {
  final list = ref.watch(accountsStreamProvider).asData?.value ?? const [];
  return {for (final a in list) a.id: a};
});

/// Each account's balance today: its opening balance, plus income and minus
/// expenses put against it, plus transfers in and minus transfers out.
///
/// Card charges never touch an account (they are debt on the card), and
/// entries for an account that no longer exists are ignored.
Map<String, double> accountBalancesFor(
  Iterable<AccountModel> accounts,
  Iterable<TransactionModel> transactions,
  Iterable<TransferModel> transfers,
) {
  final balances = {for (final a in accounts) a.id: a.openingBalance};
  for (final t in transactions) {
    final id = t.accountId;
    if (id == null || t.isOnCard || t.isDeleted) continue;
    final current = balances[id];
    if (current == null) continue;
    balances[id] = t.type == TransactionType.income
        ? current + t.amount
        : current - t.amount;
  }
  for (final x in transfers) {
    if (balances.containsKey(x.fromAccountId)) {
      balances[x.fromAccountId] = balances[x.fromAccountId]! - x.amount;
    }
    if (balances.containsKey(x.toAccountId)) {
      balances[x.toAccountId] = balances[x.toAccountId]! + x.amount;
    }
  }
  return balances;
}

/// Live balances from the local ledger, right offline and the moment an
/// entry is saved.
final accountBalancesProvider = Provider<Map<String, double>>((ref) {
  final accounts = ref.watch(accountsStreamProvider).asData?.value ?? const [];
  final transactions =
      ref.watch(allTransactionsStreamProvider).asData?.value ?? const [];
  final transfers =
      ref.watch(transfersStreamProvider).asData?.value ?? const [];
  return accountBalancesFor(accounts, transactions, transfers);
});

/// The account a new entry starts on: the one used last, while it exists.
final lastAccountIdProvider = Provider<String?>((ref) {
  final id = ref
      .watch(sharedPreferencesProvider)
      .getString(AccountActionsNotifier.lastAccountKey);
  return ref.watch(accountLookupProvider).containsKey(id) ? id : null;
});

class AccountActionsNotifier extends Notifier<AsyncValue<void>> {
  static const lastAccountKey = 'last_account_id';

  @override
  AsyncValue<void> build() => const AsyncData(null);

  AccountRepository get _repo => ref.read(accountRepositoryProvider);

  /// Runs [body] for the signed-in user. Returns its value, or null when
  /// signed out or the write failed (the failure is left in [state]).
  Future<({T? value, bool ok})> _run<T>(
    Future<Result<T>> Function(String uid) body,
  ) async {
    final uid = ref.read(currentUidProvider);
    if (uid == null) return (value: null, ok: false);
    state = const AsyncLoading();
    final result = await body(uid);
    return result.when(
      success: (value) {
        state = const AsyncData(null);
        return (value: value, ok: true);
      },
      failure: (f) {
        state = AsyncError(f, StackTrace.current);
        return (value: null, ok: false);
      },
    );
  }

  Future<AccountModel?> addAccount(AccountModel account) async =>
      (await _run((uid) => _repo.addAccount(uid, account))).value;

  Future<bool> updateAccount(AccountModel account) async =>
      (await _run((uid) => _repo.updateAccount(uid, account))).ok;

  Future<bool> deleteAccount(String id) async =>
      (await _run((uid) => _repo.deleteAccount(uid, id))).ok;

  Future<TransferModel?> addTransfer(TransferModel transfer) async =>
      (await _run((uid) => _repo.addTransfer(uid, transfer))).value;

  Future<bool> deleteTransfer(String id) async =>
      (await _run((uid) => _repo.deleteTransfer(uid, id))).ok;

  /// Remembers [accountId] as the default for the next entry.
  Future<void> rememberLast(String? accountId) async {
    final prefs = ref.read(sharedPreferencesProvider);
    if (accountId == null) {
      await prefs.remove(lastAccountKey);
    } else {
      await prefs.setString(lastAccountKey, accountId);
    }
    ref.invalidate(lastAccountIdProvider);
  }
}

final accountActionsProvider =
    NotifierProvider<AccountActionsNotifier, AsyncValue<void>>(
      AccountActionsNotifier.new,
    );
