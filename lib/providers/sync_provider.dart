import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/sync/background_sync.dart';
import '../core/sync/sync_manager.dart';
import '../data/local/transaction_local_store.dart';
import '../data/repositories/offline_transaction_repository.dart';
import 'auth_provider.dart';
import 'transaction_provider.dart';

/// The Hive-backed store. Its box is opened/closed as the signed-in user
/// changes, by [localStoreReadyProvider].
final transactionLocalStoreProvider = Provider<TransactionLocalStore>((ref) {
  final store = TransactionLocalStore();
  ref.onDispose(store.close);
  return store;
});

final syncManagerProvider = Provider<SyncManager>((ref) {
  final manager = SyncManager(
    store: ref.watch(transactionLocalStoreProvider),
    repository: ref.watch(transactionRepositoryProvider),
  );
  ref.onDispose(manager.dispose);
  return manager;
});

/// Opens this user's box and starts the sync loop. Everything that reads local
/// data waits on this, which resolves as soon as Hive is ready — not when the
/// network responds.
final localStoreReadyProvider = FutureProvider<bool>((ref) async {
  final uid = ref.watch(currentUidProvider);
  final store = ref.watch(transactionLocalStoreProvider);
  final manager = ref.watch(syncManagerProvider);

  if (uid == null) {
    await manager.stop();
    await store.close();
    await BackgroundSync.cancelAll();
    return false;
  }

  await store.open(uid);
  // Catch-up sync while the app is closed. Best-effort: never block startup.
  unawaited(BackgroundSync.registerPeriodic());
  // Fire-and-forget: local data is already usable, so the UI must not wait
  // for connectivity checks or the first cloud round-trip.
  unawaited(manager.start());
  return true;
});

final offlineTransactionRepositoryProvider =
    Provider<OfflineTransactionRepository>((ref) {
  return OfflineTransactionRepository(
    store: ref.watch(transactionLocalStoreProvider),
    remote: ref.watch(transactionRepositoryProvider),
    syncManager: ref.watch(syncManagerProvider),
  );
});

/// Live sync status for the UI chip.
final syncStateProvider = StreamProvider<SyncState>((ref) {
  final manager = ref.watch(syncManagerProvider);
  return manager.stateStream.map((s) => s);
});

/// The current value without waiting for a stream event.
final currentSyncStateProvider = Provider<SyncState>((ref) {
  return ref.watch(syncStateProvider).asData?.value ??
      ref.watch(syncManagerProvider).state;
});
