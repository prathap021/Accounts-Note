import 'package:flutter_test/flutter_test.dart';
import 'package:income_expense_tracker/data/local/sync_status.dart';

import '../../support/fixtures.dart';

/// The local store is the single source the UI renders from, so its ordering,
/// isolation and change notifications are load-bearing.
void main() {
  late HiveHarness hive;

  setUp(() async {
    hive = HiveHarness();
    await hive.setUp();
  });

  tearDown(() => hive.tearDown());

  test('returns transactions newest first', () async {
    await hive.store.putAll([
      txFixture(id: 'older', date: DateTime(2026, 9, 1)),
      txFixture(id: 'newest', date: DateTime(2026, 9, 20)),
      txFixture(id: 'middle', date: DateTime(2026, 9, 10)),
    ]);

    expect(hive.store.getAll().map((t) => t.id), ['newest', 'middle', 'older']);
  });

  test('getById finds a record, or returns null', () async {
    await hive.store.put(txFixture(id: 'known'));
    expect(hive.store.getById('known')?.id, 'known');
    expect(hive.store.getById('missing'), isNull);
  });

  test('put overwrites rather than duplicating the same id', () async {
    await hive.store.put(txFixture(id: 'same', amount: 10));
    await hive.store.put(txFixture(id: 'same', amount: 20));

    expect(hive.store.getAll(), hasLength(1));
    expect(hive.store.getAll().single.amount, 20);
  });

  group('pending queue', () {
    test('counts only records that owe a write', () async {
      await hive.store.putAll([
        txFixture(id: 'clean').copyWith(syncStatus: SyncStatus.synced),
        txFixture(id: 'dirty').copyWith(
          syncStatus: SyncStatus.pending,
          pendingOp: PendingOp.create,
        ),
      ]);

      expect(hive.store.pendingCount, 1);
      expect(hive.store.pending().single.id, 'dirty');
    });

    test('separates failed from pending', () async {
      await hive.store.putAll([
        txFixture(id: 'p').copyWith(
          syncStatus: SyncStatus.pending,
          pendingOp: PendingOp.create,
        ),
        txFixture(id: 'f').copyWith(
          syncStatus: SyncStatus.failed,
          pendingOp: PendingOp.create,
        ),
      ]);

      expect(hive.store.pendingCount, 1);
      expect(hive.store.failedCount, 1);
    });

    test('drains oldest first, so the user\'s order is preserved', () async {
      await hive.store.putAll([
        txFixture(id: 'second', updatedAt: DateTime(2026, 9, 2)).copyWith(
          pendingOp: PendingOp.create,
          syncStatus: SyncStatus.pending,
        ),
        txFixture(id: 'first', updatedAt: DateTime(2026, 9, 1)).copyWith(
          pendingOp: PendingOp.create,
          syncStatus: SyncStatus.pending,
        ),
      ]);

      expect(hive.store.pending().map((t) => t.id), ['first', 'second']);
    });

    test('tombstones stay in the queue but leave the visible list', () async {
      await hive.store.put(txFixture(id: 'gone').copyWith(
        pendingOp: PendingOp.delete,
        syncStatus: SyncStatus.pending,
      ));

      expect(hive.store.getAll(), isEmpty);
      expect(hive.store.pending(), hasLength(1));
    });
  });

  group('watch', () {
    test('emits the current contents immediately', () async {
      await hive.store.put(txFixture(id: 'seeded'));
      final first = await hive.store.watch().first;
      expect(first.single.id, 'seeded');
    });

    test('emits again when a record is written', () async {
      final emissions = <int>[];
      final sub = hive.store.watch().listen((items) => emissions.add(items.length));
      // Let the stream deliver its initial snapshot before mutating.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(emissions, [0], reason: 'starts from the current state');

      await hive.store.put(txFixture(id: 'one'));
      await hive.store.put(txFixture(id: 'two'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await sub.cancel();

      expect(emissions.last, 2);
      expect(emissions.length, greaterThan(1), reason: 'change notifications fire');
    });

    test('emits when a record is removed', () async {
      await hive.store.put(txFixture(id: 'one'));
      final emissions = <int>[];
      final sub = hive.store.watch().listen((items) => emissions.add(items.length));
      await Future<void>.delayed(const Duration(milliseconds: 20));

      await hive.store.remove('one');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await sub.cancel();

      expect(emissions.last, 0);
    });
  });

  group('reconcileFromCloud', () {
    test('adds records the cloud has and we do not', () async {
      await hive.store.reconcileFromCloud([
        txFixture(id: 'remote-1').copyWith(syncStatus: SyncStatus.synced),
      ]);
      expect(hive.store.getAll().single.id, 'remote-1');
    });

    test('drops records the cloud no longer has', () async {
      await hive.store.put(
        txFixture(id: 'stale').copyWith(syncStatus: SyncStatus.synced),
      );
      await hive.store.reconcileFromCloud([]);
      expect(hive.store.getAll(), isEmpty);
    });

    test('never overwrites a record that still owes a write', () async {
      await hive.store.put(txFixture(id: 'mine', amount: 999).copyWith(
        syncStatus: SyncStatus.pending,
        pendingOp: PendingOp.update,
      ));

      await hive.store.reconcileFromCloud([
        txFixture(id: 'mine', amount: 1).copyWith(syncStatus: SyncStatus.synced),
      ]);

      expect(hive.store.getById('mine')!.amount, 999);
    });

    test('never drops a pending record just because the cloud lacks it',
        () async {
      await hive.store.put(txFixture(id: 'brand-new').copyWith(
        syncStatus: SyncStatus.pending,
        pendingOp: PendingOp.create,
      ));

      await hive.store.reconcileFromCloud([]);

      expect(hive.store.getById('brand-new'), isNotNull,
          reason: 'it has not been pushed yet; dropping it would lose data');
    });
  });

  group('per-user isolation', () {
    test('a different uid gets a different ledger', () async {
      await hive.store.put(txFixture(id: 'user-1-tx'));

      await hive.store.open('user-2');
      expect(hive.store.getAll(), isEmpty,
          reason: 'one account must never see another account\'s data');

      await hive.store.open(testUid);
      expect(hive.store.getAll().single.id, 'user-1-tx');
    });

    test('clear wipes the signed-in ledger', () async {
      await hive.store.put(txFixture());
      await hive.store.clear();
      expect(hive.store.getAll(), isEmpty);
    });
  });

  group('closed store', () {
    test('reads degrade to empty instead of throwing', () async {
      await hive.store.close();
      expect(hive.store.getAll(), isEmpty);
      expect(hive.store.pending(), isEmpty);
      expect(hive.store.getById('anything'), isNull);
      expect(hive.store.isOpen, isFalse);
    });
  });
}
