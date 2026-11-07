import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/constants/app_constants.dart';
import '../../core/utils/result.dart';
import '../../models/account_model.dart';

/// The user's accounts and the transfers between them, in Firestore.
///
/// Like credit cards, writes trust the local cache when the server is slow
/// to answer, so adding an account or a transfer offline never hangs.
class AccountRepository {
  AccountRepository({
    FirebaseFirestore? firestore,
    this.ackTimeout = const Duration(seconds: 4),
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;
  final Duration ackTimeout;

  CollectionReference<Map<String, dynamic>> _accounts(String uid) =>
      _firestore.collection(FirestorePaths.accounts(uid));

  CollectionReference<Map<String, dynamic>> _transfers(String uid) =>
      _firestore.collection(FirestorePaths.transfers(uid));

  Future<void> _commit(Future<void> write) async {
    try {
      await write.timeout(ackTimeout);
    } on TimeoutException {
      // Queued offline; it syncs on reconnect.
    }
  }

  Future<Result<T>> _guard<T>(Future<T> Function() body) async {
    try {
      return Result.success(await body());
    } catch (e) {
      return Result.failure(AppFailure.fromException(e));
    }
  }

  Stream<List<AccountModel>> watchAccounts(String uid) =>
      _accounts(uid).snapshots().map(
        (snap) =>
            snap.docs.map(AccountModel.fromDoc).toList()
              ..sort((a, b) => a.createdAt.compareTo(b.createdAt)),
      );

  Stream<List<TransferModel>> watchTransfers(String uid) =>
      _transfers(uid).snapshots().map(
        (snap) =>
            snap.docs.map(TransferModel.fromDoc).toList()
              ..sort((a, b) => b.date.compareTo(a.date)),
      );

  Future<Result<AccountModel>> addAccount(String uid, AccountModel account) =>
      _guard(() async {
        final ref = _accounts(uid).doc();
        final saved = account.copyWith(id: ref.id);
        await _commit(ref.set(saved.toMap()));
        return saved;
      });

  Future<Result<void>> updateAccount(String uid, AccountModel account) =>
      _guard(
        () => _commit(_accounts(uid).doc(account.id).set(account.toMap())),
      );

  /// Entries and transfers that used the account keep its name, so history
  /// still reads right; they just stop counting towards any balance.
  Future<Result<void>> deleteAccount(String uid, String accountId) =>
      _guard(() => _commit(_accounts(uid).doc(accountId).delete()));

  Future<Result<TransferModel>> addTransfer(
    String uid,
    TransferModel transfer,
  ) => _guard(() async {
    final ref = _transfers(uid).doc();
    final saved = transfer.withId(ref.id);
    await _commit(ref.set(saved.toMap()));
    return saved;
  });

  Future<Result<void>> deleteTransfer(String uid, String transferId) =>
      _guard(() => _commit(_transfers(uid).doc(transferId).delete()));
}
