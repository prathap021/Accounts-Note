import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:income_expense_tracker/core/constants/app_constants.dart';
import 'package:income_expense_tracker/data/local/sync_status.dart';
import 'package:income_expense_tracker/models/transaction_model.dart';

import '../../support/fixtures.dart';

/// The local map is the on-disk Hive format. If a round-trip ever loses a
/// field, users silently lose data on the next app launch — so every field is
/// asserted explicitly rather than by comparing whole objects.
void main() {
  group('local (Hive) serialization', () {
    test('round-trips every field', () {
      final original = txFixture(
        id: 'tx-42',
        type: TransactionType.income,
        amount: 1234.56,
        categoryId: 'cat-salary',
        categoryName: 'Salary',
        note: 'March payout',
        paymentMethod: 'Bank Transfer',
        date: DateTime(2026, 3, 1, 9, 30),
      ).copyWith(
        syncStatus: SyncStatus.failed,
        pendingOp: PendingOp.update,
        lastSyncError: 'boom',
        retryCount: 3,
      );

      final restored =
          TransactionModel.fromLocalMap(original.toLocalMap());

      expect(restored.id, 'tx-42');
      expect(restored.type, TransactionType.income);
      expect(restored.amount, 1234.56);
      expect(restored.categoryId, 'cat-salary');
      expect(restored.categoryName, 'Salary');
      expect(restored.note, 'March payout');
      expect(restored.paymentMethod, 'Bank Transfer');
      expect(restored.date, DateTime(2026, 3, 1, 9, 30));
      expect(restored.syncStatus, SyncStatus.failed);
      expect(restored.pendingOp, PendingOp.update);
      expect(restored.lastSyncError, 'boom');
      expect(restored.retryCount, 3);
    });

    test('preserves nullable fields as null', () {
      final restored = TransactionModel.fromLocalMap(
        txFixture(note: null, paymentMethod: null).toLocalMap(),
      );
      expect(restored.note, isNull);
      expect(restored.paymentMethod, isNull);
      expect(restored.lastSyncError, isNull);
    });

    test('stores dates as epoch millis, not objects', () {
      final map = txFixture().toLocalMap();
      expect(map['date'], isA<int>());
      expect(map['createdAt'], isA<int>());
      expect(map['updatedAt'], isA<int>());
    });

    test('survives a map missing newer keys', () {
      // Simulates a box written by an older build.
      final map = txFixture().toLocalMap()
        ..remove('syncStatus')
        ..remove('pendingOp')
        ..remove('retryCount');

      final restored = TransactionModel.fromLocalMap(map);

      expect(restored.pendingOp, PendingOp.none);
      expect(restored.retryCount, 0);
      expect(restored.syncStatus, SyncStatus.pending,
          reason: 'unknown state is treated as needing a push, never as synced');
    });

    test('falls back to expense for an unrecognised type', () {
      final map = txFixture().toLocalMap()..['type'] = 'nonsense';
      expect(TransactionModel.fromLocalMap(map).type, TransactionType.expense);
    });

    test('accepts an int amount from disk', () {
      final map = txFixture().toLocalMap()..['amount'] = 250;
      expect(TransactionModel.fromLocalMap(map).amount, 250.0);
    });
  });

  group('cloud serialization', () {
    test('round-trips through Firestore', () async {
      final firestore = FakeFirebaseFirestore();
      final original = txFixture(id: 'tx-cloud', amount: 99.5);
      await seedCloudTransactions(firestore, [original]);

      final doc = await firestore
          .collection(FirestorePaths.transactions(testUid))
          .doc('tx-cloud')
          .get();
      final restored = TransactionModel.fromDoc(doc);

      expect(restored.id, 'tx-cloud');
      expect(restored.amount, 99.5);
      expect(restored.categoryName, original.categoryName);
      expect(restored.date, original.date);
    });

    test('anything read from the cloud counts as synced', () async {
      final firestore = FakeFirebaseFirestore();
      await seedCloudTransactions(firestore, [txFixture()]);
      final doc = await firestore
          .collection(FirestorePaths.transactions(testUid))
          .doc('tx-1')
          .get();

      final restored = TransactionModel.fromDoc(doc);

      expect(restored.syncStatus, SyncStatus.synced);
      expect(restored.pendingSync, isFalse);
    });
  });

  group('derived state', () {
    test('pendingSync covers both in-flight states', () {
      expect(txFixture().copyWith(syncStatus: SyncStatus.pending).pendingSync,
          isTrue);
      expect(txFixture().copyWith(syncStatus: SyncStatus.syncing).pendingSync,
          isTrue);
      expect(txFixture().copyWith(syncStatus: SyncStatus.synced).pendingSync,
          isFalse);
      expect(txFixture().copyWith(syncStatus: SyncStatus.failed).pendingSync,
          isFalse,
          reason: 'failed is settled, not in flight');
    });

    test('isDeleted marks tombstones', () {
      expect(txFixture().copyWith(pendingOp: PendingOp.delete).isDeleted, isTrue);
      expect(txFixture().isDeleted, isFalse);
    });
  });

  group('copyWith', () {
    test('leaves untouched fields alone', () {
      final updated = txFixture().copyWith(amount: 500);
      expect(updated.amount, 500);
      expect(updated.categoryName, 'Food');
      expect(updated.note, 'Lunch');
    });

    test('clearSyncError wipes the error, unlike passing null', () {
      final failed = txFixture().copyWith(lastSyncError: 'boom');
      expect(failed.copyWith(amount: 1).lastSyncError, 'boom',
          reason: 'null means "unchanged" for nullable fields');
      expect(failed.copyWith(clearSyncError: true).lastSyncError, isNull);
    });
  });
}
