import 'dart:async';

import 'package:hive_ce_flutter/hive_flutter.dart';

import '../../models/transaction_model.dart';
import 'sync_status.dart';

/// Hive-backed store of the user's transactions — the primary source the UI
/// reads from. Every write lands here first and is visible immediately;
/// [SyncManager] is what later reconciles it with Firestore.
///
/// One box per user id, so signing into a different account cannot surface the
/// previous account's ledger.
class TransactionLocalStore {
  static const _boxPrefix = 'transactions_';

  Box<Map>? _box;
  String? _uid;

  String? get uid => _uid;
  bool get isOpen => _box?.isOpen ?? false;

  static String boxNameFor(String uid) => '$_boxPrefix$uid';

  /// Opens the box for [uid]. Safe to call repeatedly; re-opens only when the
  /// signed-in user actually changes.
  Future<void> open(String uid) async {
    if (_uid == uid && isOpen) return;
    await close();
    _box = await Hive.openBox<Map>(boxNameFor(uid));
    _uid = uid;
  }

  Future<void> close() async {
    await _box?.close();
    _box = null;
    _uid = null;
  }

  /// Wipes this user's local ledger — used on sign-out and account deletion so
  /// nothing is left on the device.
  Future<void> clear() async {
    await _box?.clear();
  }

  List<TransactionModel> _readAll({bool includeDeleted = false}) {
    final box = _box;
    if (box == null || !box.isOpen) return const [];
    final items = box.values
        .map(TransactionModel.fromLocalMap)
        .where((t) => includeDeleted || !t.isDeleted)
        .toList();
    items.sort((a, b) => b.date.compareTo(a.date));
    return items;
  }

  /// Newest first, excluding records tombstoned for deletion.
  List<TransactionModel> getAll() => _readAll();

  TransactionModel? getById(String id) {
    final raw = _box?.get(id);
    return raw == null ? null : TransactionModel.fromLocalMap(raw);
  }

  /// Everything still owing a cloud write, oldest first so the queue drains in
  /// the order the user created it.
  List<TransactionModel> pending() {
    final items = _readAll(includeDeleted: true)
        .where((t) => t.pendingOp != PendingOp.none)
        .toList();
    items.sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
    return items;
  }

  int get pendingCount =>
      pending().where((t) => t.syncStatus != SyncStatus.failed).length;

  int get failedCount =>
      pending().where((t) => t.syncStatus == SyncStatus.failed).length;

  /// Emits the current list immediately, then again on every local change, so
  /// the UI never waits on the network for its first frame.
  Stream<List<TransactionModel>> watch() async* {
    yield getAll();
    final box = _box;
    if (box == null || !box.isOpen) return;
    yield* box.watch().map((_) => getAll());
  }

  Future<void> put(TransactionModel tx) async {
    await _box?.put(tx.id, tx.toLocalMap());
  }

  /// Bulk upsert used by the cloud pull. Writes once so watchers rebuild a
  /// single time rather than once per record.
  Future<void> putAll(Iterable<TransactionModel> items) async {
    final box = _box;
    if (box == null || !box.isOpen) return;
    await box.putAll({for (final t in items) t.id: t.toLocalMap()});
  }

  Future<void> remove(String id) async {
    await _box?.delete(id);
  }

  Future<void> removeAll(Iterable<String> ids) async {
    final box = _box;
    if (box == null || !box.isOpen) return;
    await box.deleteAll(ids);
  }

  /// Replaces the local set with what the cloud returned, while protecting any
  /// record that still owes a write — those are the user's newest intent and
  /// must not be clobbered by a stale server copy.
  Future<void> reconcileFromCloud(List<TransactionModel> remote) async {
    final box = _box;
    if (box == null || !box.isOpen) return;

    final locallyPending = {
      for (final t in pending()) t.id,
    };

    final toWrite = <String, Map>{};
    for (final t in remote) {
      if (locallyPending.contains(t.id)) continue;
      toWrite[t.id] = t.toLocalMap();
    }

    // Anything the cloud no longer has, and that we are not still pushing,
    // was deleted elsewhere — drop it locally too.
    final remoteIds = remote.map((t) => t.id).toSet();
    final stale = _readAll(includeDeleted: true)
        .where((t) =>
            !remoteIds.contains(t.id) && !locallyPending.contains(t.id))
        .map((t) => t.id)
        .toList();

    if (toWrite.isNotEmpty) await box.putAll(toWrite);
    if (stale.isNotEmpty) await box.deleteAll(stale);
  }
}
