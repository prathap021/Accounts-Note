import 'dart:async';

import 'package:uuid/uuid.dart';

import '../../core/constants/app_constants.dart';
import '../../core/sync/sync_manager.dart';
import '../../core/utils/result.dart';
import '../../models/transaction_model.dart';
import '../local/daily_usage_store.dart';
import '../local/sync_status.dart';
import '../local/transaction_local_store.dart';
import 'transaction_repository.dart';

/// The write path for transactions: Hive first, cloud second.
///
/// Every mutation lands in the local store and returns immediately, so the UI
/// updates at local-write speed whether or not there is a network. The cloud
/// push is handed to [SyncManager] and never awaited on the user's behalf.
class OfflineTransactionRepository {
  final TransactionLocalStore store;
  final TransactionRepository remote;
  final SyncManager syncManager;
  final Uuid _uuid;

  /// Whether a write should immediately kick a background sync. Always true in
  /// the app; tests turn it off so they can drive sync explicitly instead of
  /// racing a fire-and-forget future.
  final bool autoSync;

  /// Counts each new entry until the server has counted it, for the daily
  /// limit. Optional so tests that do not care about limits can skip it.
  final DailyUsageStore? usageStore;

  OfflineTransactionRepository({
    required this.store,
    required this.remote,
    required this.syncManager,
    this.autoSync = true,
    this.usageStore,
    Uuid? uuid,
  }) : _uuid = uuid ?? const Uuid();

  /// Newest first, straight from Hive — available on the first frame.
  List<TransactionModel> currentTransactions() => store.getAll();

  Stream<List<TransactionModel>> watchTransactions({
    TransactionFilter filter = const TransactionFilter(),
  }) {
    return store.watch().map(
          (items) => filter.isEmpty ? items : items.where(filter.matches).toList(),
        );
  }

  /// Saves locally and returns at once. The id is generated on the device so
  /// the eventual cloud write is idempotent.
  Future<Result<TransactionModel>> addTransaction(TransactionModel tx) async {
    try {
      final now = DateTime.now();
      final saved = tx.copyWith(
        id: tx.id.isEmpty ? _uuid.v4() : tx.id,
        createdAt: now,
        updatedAt: now,
        // Pins the local day this entry counts against, however late it
        // reaches the server and whatever timezone the phone is in by then.
        createdTzOffsetMinutes: now.timeZoneOffset.inMinutes,
        syncStatus: SyncStatus.pending,
        pendingOp: PendingOp.create,
        retryCount: 0,
        clearSyncError: true,
      );
      await store.put(saved);
      final uid = store.uid;
      if (uid != null) {
        await usageStore?.recordCreated(uid, saved.usageDay, saved.type);
      }
      _kickSync();
      return Result.success(saved);
    } catch (e) {
      return Result.failure(AppFailure.fromException(e));
    }
  }

  Future<Result<void>> updateTransaction(TransactionModel tx) async {
    try {
      final existing = store.getById(tx.id);
      // A record still waiting to be created stays a create, otherwise the
      // cloud would get an update for a document that does not exist yet.
      final op = existing?.pendingOp == PendingOp.create
          ? PendingOp.create
          : PendingOp.update;
      await store.put(tx.copyWith(
        updatedAt: DateTime.now(),
        syncStatus: SyncStatus.pending,
        pendingOp: op,
        retryCount: 0,
        clearSyncError: true,
      ));
      _kickSync();
      return Result.success(null);
    } catch (e) {
      return Result.failure(AppFailure.fromException(e));
    }
  }

  /// Deletes locally at once and returns the record as it was, so the user
  /// can undo. The cloud delete waits out [SyncManager.deleteGrace] first:
  /// an undo inside that window just puts the record back, and nothing ever
  /// reaches the server.
  Future<Result<TransactionModel?>> deleteTransaction(String txId) async {
    try {
      final existing = store.getById(txId);
      if (existing == null) return Result.success(null);

      if (existing.pendingOp == PendingOp.create) {
        // Never reached the cloud, so there is nothing to delete up there.
        await store.remove(txId);
      } else {
        // Tombstone: hidden from the UI now, deleted in the cloud later.
        await store.put(existing.copyWith(
          updatedAt: DateTime.now(),
          syncStatus: SyncStatus.pending,
          pendingOp: PendingOp.delete,
          retryCount: 0,
          clearSyncError: true,
        ));
        if (autoSync) {
          unawaited(Future<void>.delayed(
            syncManager.deleteGrace + const Duration(milliseconds: 500),
            () => syncManager.syncNow(),
          ));
        }
      }
      return Result.success(existing);
    } catch (e) {
      return Result.failure(AppFailure.fromException(e));
    }
  }

  /// Undo for [deleteTransaction]: the record exactly as it was. A record
  /// that was still waiting to be created goes back to waiting, and keeps
  /// the entry it already used from the day's allowance.
  Future<Result<void>> restoreDeleted(TransactionModel previous) async {
    try {
      await store.put(previous);
      _kickSync();
      return Result.success(null);
    } catch (e) {
      return Result.failure(AppFailure.fromException(e));
    }
  }

  /// Totals computed over the local store, so the dashboard works offline.
  /// Income and expense totals for the window.
  ///
  /// [cashOnly] drops anything charged to a credit card, which is what the
  /// dashboard wants: a card swipe is debt, not cash out. Off by default so
  /// reports and budgets keep totalling every transaction.
  Map<TransactionType, double> sumByType({
    required DateTime start,
    required DateTime end,
    bool cashOnly = false,
  }) {
    double income = 0, expense = 0;
    for (final t in store.getAll()) {
      if (t.date.isBefore(start) || t.date.isAfter(end)) continue;
      if (cashOnly && t.isOnCard) continue;
      if (t.type == TransactionType.income) {
        income += t.amount;
      } else {
        expense += t.amount;
      }
    }
    return {
      TransactionType.income: income,
      TransactionType.expense: expense,
    };
  }

  /// Income minus expenses for everything dated strictly before [before].
  ///
  /// This is what a period opens with: whatever was left at the end of every
  /// earlier month. Derived from the ledger rather than stored, so editing or
  /// deleting an old transaction corrects every later month automatically.
  /// Negative when earlier spending exceeded earlier income.
  double balanceBefore(DateTime before, {bool cashOnly = false}) {
    double net = 0;
    for (final t in store.getAll()) {
      if (!t.date.isBefore(before)) continue;
      if (cashOnly && t.isOnCard) continue;
      net += t.type == TransactionType.income ? t.amount : -t.amount;
    }
    return net;
  }

  Map<String, double> categoryBreakdown({
    required DateTime start,
    required DateTime end,
    TransactionType type = TransactionType.expense,
    bool cashOnly = false,
  }) {
    final totals = <String, double>{};
    for (final t in store.getAll()) {
      if (t.type != type) continue;
      if (t.date.isBefore(start) || t.date.isAfter(end)) continue;
      if (cashOnly && t.isOnCard) continue;
      totals[t.categoryName] = (totals[t.categoryName] ?? 0) + t.amount;
    }
    return totals;
  }

  /// What was charged to credit cards in the window — the other half of
  /// [sumByType] with `cashOnly: true`. Only expenses count; a refund credited
  /// back to a card reduces the balance owed rather than adding to spend.
  double creditCardSpend({required DateTime start, required DateTime end}) {
    double total = 0;
    for (final t in store.getAll()) {
      if (!t.isOnCard || t.type != TransactionType.expense) continue;
      if (t.date.isBefore(start) || t.date.isAfter(end)) continue;
      total += t.amount;
    }
    return total;
  }

  /// Fire-and-forget: a write must never wait on the network.
  void _kickSync() {
    if (!autoSync) return;
    unawaited(syncManager.syncNow());
  }
}
