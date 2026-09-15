import 'dart:async';

import 'package:uuid/uuid.dart';

import '../../core/constants/app_constants.dart';
import '../../core/sync/sync_manager.dart';
import '../../core/utils/result.dart';
import '../../models/transaction_model.dart';
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

  OfflineTransactionRepository({
    required this.store,
    required this.remote,
    required this.syncManager,
    this.autoSync = true,
    Uuid? uuid,
  }) : _uuid = uuid ?? const Uuid();

  /// Newest first, straight from Hive — available on the first frame.
  List<TransactionModel> currentTransactions() => store.getAll();

  Stream<List<TransactionModel>> watchTransactions({
    TransactionFilter filter = const TransactionFilter(),
  }) {
    return store.watch().map((items) => _applyFilter(items, filter));
  }

  List<TransactionModel> _applyFilter(
    List<TransactionModel> items,
    TransactionFilter filter,
  ) {
    var result = items;
    if (filter.startDate != null) {
      final start = filter.startDate!;
      result = result.where((t) => !t.date.isBefore(start)).toList();
    }
    if (filter.endDate != null) {
      final end = filter.endDate!;
      result = result.where((t) => !t.date.isAfter(end)).toList();
    }
    if (filter.type != null) {
      result = result.where((t) => t.type == filter.type).toList();
    }
    if (filter.categoryId != null) {
      result = result.where((t) => t.categoryId == filter.categoryId).toList();
    }
    if (filter.paymentMethod != null) {
      result =
          result.where((t) => t.paymentMethod == filter.paymentMethod).toList();
    }
    final query = filter.searchQuery?.trim().toLowerCase();
    if (query != null && query.isNotEmpty) {
      result = result.where((t) {
        return t.categoryName.toLowerCase().contains(query) ||
            (t.note?.toLowerCase().contains(query) ?? false) ||
            (t.paymentMethod?.toLowerCase().contains(query) ?? false);
      }).toList();
    }
    return result;
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
        syncStatus: SyncStatus.pending,
        pendingOp: PendingOp.create,
        retryCount: 0,
        clearSyncError: true,
      );
      await store.put(saved);
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

  Future<Result<void>> deleteTransaction(String txId) async {
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
      }
      _kickSync();
      return Result.success(null);
    } catch (e) {
      return Result.failure(AppFailure.fromException(e));
    }
  }

  /// Totals computed over the local store, so the dashboard works offline.
  Map<TransactionType, double> sumByType({
    required DateTime start,
    required DateTime end,
  }) {
    double income = 0, expense = 0;
    for (final t in store.getAll()) {
      if (t.date.isBefore(start) || t.date.isAfter(end)) continue;
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

  Map<String, double> categoryBreakdown({
    required DateTime start,
    required DateTime end,
    TransactionType type = TransactionType.expense,
  }) {
    final totals = <String, double>{};
    for (final t in store.getAll()) {
      if (t.type != type) continue;
      if (t.date.isBefore(start) || t.date.isAfter(end)) continue;
      totals[t.categoryName] = (totals[t.categoryName] ?? 0) + t.amount;
    }
    return totals;
  }

  /// Fire-and-forget: a write must never wait on the network.
  void _kickSync() {
    if (!autoSync) return;
    unawaited(syncManager.syncNow());
  }
}
