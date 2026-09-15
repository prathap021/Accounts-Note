import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import '../../data/local/sync_status.dart';
import '../../data/local/transaction_local_store.dart';
import '../../data/repositories/transaction_repository.dart';

/// Overall sync state, surfaced to the UI as a status chip.
enum SyncPhase { idle, syncing, offline, failed }

@immutable
class SyncState {
  final SyncPhase phase;
  final bool isOnline;
  final int pendingCount;
  final int failedCount;
  final DateTime? lastSyncedAt;

  const SyncState({
    this.phase = SyncPhase.idle,
    this.isOnline = true,
    this.pendingCount = 0,
    this.failedCount = 0,
    this.lastSyncedAt,
  });

  /// What to show the user, in one word.
  String get label => switch (phase) {
        SyncPhase.syncing => 'Syncing',
        SyncPhase.offline => pendingCount > 0 ? 'Pending' : 'Offline',
        SyncPhase.failed => 'Failed',
        SyncPhase.idle => pendingCount > 0 ? 'Pending' : 'Synced',
      };

  bool get hasWork => pendingCount > 0 || failedCount > 0;

  SyncState copyWith({
    SyncPhase? phase,
    bool? isOnline,
    int? pendingCount,
    int? failedCount,
    DateTime? lastSyncedAt,
  }) {
    return SyncState(
      phase: phase ?? this.phase,
      isOnline: isOnline ?? this.isOnline,
      pendingCount: pendingCount ?? this.pendingCount,
      failedCount: failedCount ?? this.failedCount,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
    );
  }
}

/// Drains the local pending queue to Firestore and pulls the cloud back down.
///
/// Contract:
/// - Local Hive is authoritative for the UI; this never blocks a user write.
/// - Every push is keyed by the record's client-generated id and uses
///   `set(..., merge)`, so replaying the queue cannot create duplicates.
/// - A failure marks the record [SyncStatus.failed] and leaves the data
///   untouched; the next run retries it.
class SyncManager {
  final TransactionLocalStore store;
  final TransactionRepository repository;
  final Connectivity connectivity;

  /// Give up auto-retrying after this many attempts; the record stays on the
  /// device and is retried on the next manual sync or app start.
  static const maxAutoRetries = 5;

  SyncManager({
    required this.store,
    required this.repository,
    Connectivity? connectivity,
  }) : connectivity = connectivity ?? Connectivity();

  final _stateController = StreamController<SyncState>.broadcast();
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  SyncState _state = const SyncState();
  SyncState get state => _state;
  Stream<SyncState> get stateStream => _stateController.stream;

  bool _syncing = false;
  bool _disposed = false;

  void _emit(SyncState next) {
    if (_disposed) return;
    _state = next;
    _stateController.add(next);
  }

  void _refreshCounts({SyncPhase? phase, DateTime? lastSyncedAt}) {
    _emit(_state.copyWith(
      phase: phase,
      pendingCount: store.pendingCount,
      failedCount: store.failedCount,
      lastSyncedAt: lastSyncedAt,
    ));
  }

  /// Starts watching connectivity and kicks off an initial sync. Called once
  /// the user is known and their box is open.
  Future<void> start() async {
    _disposed = false;
    await _connectivitySub?.cancel();
    _connectivitySub = connectivity.onConnectivityChanged.listen((results) {
      final online = _isOnline(results);
      _emit(_state.copyWith(
        isOnline: online,
        phase: online ? _state.phase : SyncPhase.offline,
      ));
      // Regaining a connection is the moment to flush whatever piled up.
      if (online) unawaited(syncNow());
    });

    final online = _isOnline(await connectivity.checkConnectivity());
    _emit(_state.copyWith(
      isOnline: online,
      phase: online ? SyncPhase.idle : SyncPhase.offline,
      pendingCount: store.pendingCount,
      failedCount: store.failedCount,
    ));
    if (online) unawaited(syncNow());
  }

  Future<void> stop() async {
    await _connectivitySub?.cancel();
    _connectivitySub = null;
  }

  Future<void> dispose() async {
    _disposed = true;
    await stop();
    await _stateController.close();
  }

  static bool _isOnline(List<ConnectivityResult> results) =>
      results.any((r) => r != ConnectivityResult.none);

  Future<bool> isOnline() async =>
      _isOnline(await connectivity.checkConnectivity());

  /// Pushes pending work, then pulls the cloud state down. Safe to call from
  /// anywhere; overlapping calls collapse into the one already running.
  Future<void> syncNow({bool includeFailed = true}) async {
    final uid = store.uid;
    if (_syncing || uid == null || _disposed) return;

    if (!await isOnline()) {
      _refreshCounts(phase: SyncPhase.offline);
      return;
    }

    _syncing = true;
    _refreshCounts(phase: SyncPhase.syncing);

    var anyFailed = false;
    try {
      anyFailed = !await _push(uid, includeFailed: includeFailed);
      await _pull(uid);
      _refreshCounts(
        phase: anyFailed ? SyncPhase.failed : SyncPhase.idle,
        lastSyncedAt: DateTime.now(),
      );
    } catch (e) {
      debugPrint('Sync failed: $e');
      _refreshCounts(phase: SyncPhase.failed);
    } finally {
      _syncing = false;
    }
  }

  /// Drains the queue. Returns false if anything failed.
  Future<bool> _push(String uid, {required bool includeFailed}) async {
    var allOk = true;

    for (final tx in store.pending()) {
      if (_disposed) return allOk;
      if (!includeFailed && tx.syncStatus == SyncStatus.failed) continue;
      if (tx.retryCount >= maxAutoRetries && !includeFailed) continue;

      await store.put(tx.copyWith(syncStatus: SyncStatus.syncing));

      try {
        switch (tx.pendingOp) {
          case PendingOp.create:
          case PendingOp.update:
            // Keyed by the record's own id and merged, so replaying this
            // after a timeout updates the same document instead of adding
            // a second one.
            await repository.upsertTransaction(uid, tx);
            await store.put(tx.copyWith(
              syncStatus: SyncStatus.synced,
              pendingOp: PendingOp.none,
              retryCount: 0,
              clearSyncError: true,
            ));
          case PendingOp.delete:
            await repository.deleteTransactionRaw(uid, tx.id);
            // Tombstone has done its job — drop it for good.
            await store.remove(tx.id);
          case PendingOp.none:
            await store.put(tx.copyWith(syncStatus: SyncStatus.synced));
        }
      } catch (e) {
        allOk = false;
        await store.put(tx.copyWith(
          syncStatus: SyncStatus.failed,
          retryCount: tx.retryCount + 1,
          lastSyncError: e.toString(),
        ));
      }
    }

    return allOk;
  }

  /// Pulls the cloud copy down and reconciles, leaving pending records alone.
  Future<void> _pull(String uid) async {
    final result = await repository.fetchAllForSync(uid);
    await result.when(
      success: (remote) async => store.reconcileFromCloud(remote),
      failure: (f) async => debugPrint('Sync pull failed: ${f.userMessage}'),
    );
  }

  /// Clears the failed flag so the records are retried from scratch.
  Future<void> retryFailed() async {
    for (final tx in store.pending()) {
      if (tx.syncStatus == SyncStatus.failed) {
        await store.put(tx.copyWith(
          syncStatus: SyncStatus.pending,
          retryCount: 0,
          clearSyncError: true,
        ));
      }
    }
    await syncNow();
  }
}
