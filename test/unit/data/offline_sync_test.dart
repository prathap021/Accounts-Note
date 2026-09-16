import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:income_expense_tracker/core/constants/app_constants.dart';
import 'package:income_expense_tracker/core/sync/sync_manager.dart';
import 'package:income_expense_tracker/data/local/sync_status.dart';
import 'package:income_expense_tracker/data/local/transaction_local_store.dart';
import 'package:income_expense_tracker/data/repositories/offline_transaction_repository.dart';
import 'package:income_expense_tracker/data/repositories/transaction_repository.dart';
import 'package:income_expense_tracker/models/transaction_model.dart';

/// Connectivity we can flip at will.
class FakeConnectivity implements Connectivity {
  final _controller = StreamController<List<ConnectivityResult>>.broadcast();
  List<ConnectivityResult> current = [ConnectivityResult.wifi];

  void goOffline() {
    current = [ConnectivityResult.none];
    _controller.add(current);
  }

  void goOnline() {
    current = [ConnectivityResult.wifi];
    _controller.add(current);
  }

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => current;

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      _controller.stream;

  Future<void> dispose() => _controller.close();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A repository whose pushes fail, to exercise the failure path.
class FailingRepository extends TransactionRepository {
  FailingRepository(FakeFirebaseFirestore firestore)
      : super(firestore: firestore);
  int attempts = 0;

  @override
  Future<void> upsertTransaction(String uid, TransactionModel tx) async {
    attempts++;
    throw StateError('network down');
  }
}

const uid = 'user-1';

TransactionModel newTx({String id = '', double amount = 100}) =>
    TransactionModel(
      id: id,
      type: TransactionType.expense,
      amount: amount,
      categoryId: 'c1',
      categoryName: 'Food',
      note: 'Lunch',
      date: DateTime(2026, 9, 15, 12),
      paymentMethod: 'Cash',
      createdAt: DateTime(2026, 9, 15),
      updatedAt: DateTime(2026, 9, 15),
    );

void main() {
  late Directory tempDir;
  late TransactionLocalStore store;
  late FakeFirebaseFirestore firestore;
  late FakeConnectivity connectivity;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_sync_test');
    Hive.init(tempDir.path);
    store = TransactionLocalStore();
    await store.open(uid);
    firestore = FakeFirebaseFirestore();
    connectivity = FakeConnectivity();
  });

  tearDown(() async {
    await store.close();
    await Hive.deleteFromDisk();
    await connectivity.dispose();
    await tempDir.delete(recursive: true);
  });

  OfflineTransactionRepository buildRepo({TransactionRepository? remote}) {
    final cloud = remote ?? TransactionRepository(firestore: firestore);
    final manager = SyncManager(
      store: store,
      repository: cloud,
      connectivity: connectivity,
    );
    return OfflineTransactionRepository(
      store: store,
      remote: cloud,
      syncManager: manager,
      // Drive sync explicitly so assertions cannot race the automatic push.
      autoSync: false,
    );
  }

  Future<int> cloudCount() async {
    final snap =
        await firestore.collection(FirestorePaths.transactions(uid)).get();
    return snap.docs.length;
  }

  group('local-first writes', () {
    test('an added transaction is readable immediately and marked pending',
        () async {
      final repo = buildRepo();
      connectivity.goOffline();

      final result = await repo.addTransaction(newTx());
      final saved = result.when(success: (t) => t, failure: (_) => null);

      expect(saved, isNotNull);
      expect(saved!.id, isNotEmpty, reason: 'id is generated on device');
      expect(store.getAll(), hasLength(1));
      expect(store.getAll().single.syncStatus, SyncStatus.pending);
      expect(store.pendingCount, 1);
    });

    test('a delete before the record ever synced removes it outright',
        () async {
      final repo = buildRepo();
      connectivity.goOffline();
      final saved = (await repo.addTransaction(newTx()))
          .when(success: (t) => t, failure: (_) => null)!;

      await repo.deleteTransaction(saved.id);

      expect(store.getAll(), isEmpty);
      expect(store.pending(), isEmpty, reason: 'nothing to tell the cloud');
    });

    test('a delete of a synced record is tombstoned, not dropped', () async {
      final repo = buildRepo();
      final saved = (await repo.addTransaction(newTx()))
          .when(success: (t) => t, failure: (_) => null)!;
      await store.put(saved.copyWith(
        syncStatus: SyncStatus.synced,
        pendingOp: PendingOp.none,
      ));

      await repo.deleteTransaction(saved.id);

      expect(store.getAll(), isEmpty, reason: 'hidden from the UI');
      expect(store.pending().single.pendingOp, PendingOp.delete);
    });
  });

  group('sync', () {
    test('queued work is pushed once connectivity returns', () async {
      final repo = buildRepo();
      connectivity.goOffline();
      await repo.addTransaction(newTx());
      expect(await cloudCount(), 0);

      connectivity.goOnline();
      await repo.syncManager.syncNow();

      expect(await cloudCount(), 1);
      expect(store.getAll().single.syncStatus, SyncStatus.synced);
      expect(store.pendingCount, 0);
    });

    test('syncing repeatedly does not duplicate a record', () async {
      final repo = buildRepo();
      await repo.addTransaction(newTx());

      await repo.syncManager.syncNow();
      await repo.syncManager.syncNow();
      await repo.syncManager.syncNow();

      expect(await cloudCount(), 1, reason: 'same client id, merged');
      expect(store.getAll(), hasLength(1));
    });

    test('an edit made offline replaces the cloud copy rather than adding one',
        () async {
      final repo = buildRepo();
      final saved = (await repo.addTransaction(newTx(amount: 100)))
          .when(success: (t) => t, failure: (_) => null)!;
      await repo.syncManager.syncNow();

      connectivity.goOffline();
      await repo.updateTransaction(saved.copyWith(amount: 250));
      connectivity.goOnline();
      await repo.syncManager.syncNow();

      expect(await cloudCount(), 1);
      final doc = await firestore
          .collection(FirestorePaths.transactions(uid))
          .doc(saved.id)
          .get();
      expect(doc.data()!['amount'], 250);
    });

    test('a failed push keeps the data and marks it failed', () async {
      final failing = FailingRepository(firestore);
      final repo = buildRepo(remote: failing);
      await repo.addTransaction(newTx());

      await repo.syncManager.syncNow();

      expect(failing.attempts, greaterThanOrEqualTo(1));
      expect(store.getAll(), hasLength(1), reason: 'never lose local data');
      expect(store.getAll().single.syncStatus, SyncStatus.failed);
      expect(store.failedCount, 1);
      expect(store.getAll().single.lastSyncError, contains('network down'));
    });

    test('failed records are retried on the next sync', () async {
      final failing = FailingRepository(firestore);
      final repo = buildRepo(remote: failing);
      await repo.addTransaction(newTx());

      await repo.syncManager.syncNow();
      final afterFirst = failing.attempts;
      await repo.syncManager.syncNow();

      expect(failing.attempts, greaterThan(afterFirst),
          reason: 'retried, not abandoned');
      expect(store.getAll(), hasLength(1));
    });

    test('a pull does not clobber a record that still owes a write', () async {
      final repo = buildRepo();
      final saved = (await repo.addTransaction(newTx(amount: 100)))
          .when(success: (t) => t, failure: (_) => null)!;
      await repo.syncManager.syncNow();

      // Local edit that has not been pushed yet.
      connectivity.goOffline();
      await repo.updateTransaction(saved.copyWith(amount: 999));

      // A pull arriving now must not overwrite the newer local intent.
      await store.reconcileFromCloud([
        saved.copyWith(amount: 100, syncStatus: SyncStatus.synced),
      ]);

      expect(store.getAll().single.amount, 999);
    });

    test('records deleted elsewhere are dropped locally on pull', () async {
      final repo = buildRepo();
      await repo.addTransaction(newTx());
      await repo.syncManager.syncNow();
      expect(store.getAll(), hasLength(1));

      await store.reconcileFromCloud([]);

      expect(store.getAll(), isEmpty);
    });
  });

  group('restart durability', () {
    test('pending work survives closing and reopening the box', () async {
      final repo = buildRepo();
      connectivity.goOffline();
      await repo.addTransaction(newTx());

      await store.close();
      await store.open(uid);

      expect(store.getAll(), hasLength(1));
      expect(store.pendingCount, 1, reason: 'queue survives a restart');
    });
  });
}
