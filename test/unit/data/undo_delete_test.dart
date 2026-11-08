import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:accounts_note/core/constants/app_constants.dart';
import 'package:accounts_note/core/sync/sync_manager.dart';
import 'package:accounts_note/data/local/sync_status.dart';
import 'package:accounts_note/data/repositories/offline_transaction_repository.dart';
import 'package:accounts_note/data/repositories/transaction_repository.dart';

import '../../support/fixtures.dart';

class _Online implements Connectivity {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => [
    ConnectivityResult.wifi,
  ];

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      const Stream.empty();
}

/// Delete, then Undo: the entry comes back exactly as it was, and the cloud
/// never hears about a delete that was taken back.
void main() {
  final hive = HiveHarness();
  late FakeFirebaseFirestore firestore;

  setUp(() async {
    await hive.setUp();
    firestore = FakeFirebaseFirestore();
  });
  tearDown(hive.tearDown);

  OfflineTransactionRepository repo({
    Duration grace = const Duration(seconds: 6),
  }) {
    final remote = TransactionRepository(firestore: firestore);
    return OfflineTransactionRepository(
      store: hive.store,
      remote: remote,
      syncManager: SyncManager(
        store: hive.store,
        repository: remote,
        connectivity: _Online(),
        deleteGrace: grace,
      ),
      autoSync: false,
    );
  }

  Future<bool> inCloud(String id) async =>
      (await firestore.doc(FirestorePaths.transaction(testUid, id)).get())
          .exists;

  Future<void> seedSynced(String id) async {
    final tx = txFixture(id: id, date: DateTime.now());
    await firestore
        .doc(FirestorePaths.transaction(testUid, id))
        .set(tx.toMap());
    await hive.store.put(tx);
  }

  test('undo brings a synced entry back, and the cloud keeps it', () async {
    await seedSynced('t1');
    final r = repo();

    final previous = (await r.deleteTransaction(
      't1',
    )).when(success: (p) => p, failure: (_) => null);
    expect(hive.store.getAll(), isEmpty, reason: 'hidden at once');

    // A sync inside the undo window must not send the delete.
    await r.syncManager.syncNow();
    expect(await inCloud('t1'), isTrue);

    await r.restoreDeleted(previous!);
    expect(hive.store.getAll().single.id, 't1');
    expect(hive.store.getById('t1')!.pendingOp, PendingOp.none);
    await r.syncManager.syncNow();
    expect(await inCloud('t1'), isTrue);
  });

  test('without an undo, the delete is sent once the window passes', () async {
    await seedSynced('t1');
    final r = repo(grace: Duration.zero);
    await r.deleteTransaction('t1');
    await r.syncManager.syncNow();
    expect(await inCloud('t1'), isFalse);
    expect(hive.store.getById('t1'), isNull);
  });

  test('undo of an entry not uploaded yet puts it back in the queue', () async {
    final r = repo();
    final saved = (await r.addTransaction(
      txFixture(id: ''),
    )).when(success: (t) => t, failure: (_) => fail('not saved'));

    final previous = (await r.deleteTransaction(
      saved.id,
    )).when(success: (p) => p, failure: (_) => null);
    expect(hive.store.getById(saved.id), isNull);

    await r.restoreDeleted(previous!);
    final back = hive.store.getById(saved.id)!;
    expect(back.pendingOp, PendingOp.create, reason: 'still to be uploaded');
    expect(back.amount, saved.amount);
  });

  test('deleting something already gone returns nothing to undo', () async {
    final result = await repo().deleteTransaction('missing');
    expect(result.when(success: (p) => p, failure: (_) => 'failed'), isNull);
  });
}
