import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:income_expense_tracker/core/constants/app_constants.dart';
import 'package:income_expense_tracker/core/sync/sync_manager.dart';
import 'package:income_expense_tracker/data/local/daily_usage_store.dart';
import 'package:income_expense_tracker/data/local/transaction_local_store.dart';
import 'package:income_expense_tracker/data/repositories/offline_transaction_repository.dart';
import 'package:income_expense_tracker/data/repositories/transaction_repository.dart';
import 'package:income_expense_tracker/models/daily_usage.dart';
import 'package:income_expense_tracker/models/transaction_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

const uid = 'user-1';

class _Online implements Connectivity {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => [
    ConnectivityResult.wifi,
  ];

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      const Stream.empty();
}

TransactionModel newTx(TransactionType type) => TransactionModel(
  id: '',
  type: type,
  amount: 100,
  categoryId: 'c1',
  categoryName: 'Food',
  date: DateTime.now(),
  createdAt: DateTime.now(),
  updatedAt: DateTime.now(),
);

void main() {
  group('usageDayOf', () {
    test('counts against the local calendar day, not the UTC one', () {
      final t = DateTime.utc(2026, 11, 6, 20, 30);
      expect(usageDayOf(t, 330), '2026-11-07', reason: 'IST, UTC+05:30');
      expect(usageDayOf(t, 0), '2026-11-06');
      expect(usageDayOf(t, -300), '2026-11-06', reason: 'UTC-05:00');
      expect(usageDayOf(DateTime.utc(2026, 11, 7, 2), -300), '2026-11-06');
    });

    test('a transaction keeps the day it was created on', () {
      final tx = newTx(TransactionType.income).copyWith(
        createdAt: DateTime.utc(2026, 11, 6, 20, 30),
        createdTzOffsetMinutes: 330,
      );
      expect(tx.usageDay, '2026-11-07');
      final roundTrip = TransactionModel.fromLocalMap(tx.toLocalMap());
      expect(roundTrip.createdTzOffsetMinutes, 330);
      expect(tx.toMap()['createdTzOffsetMinutes'], 330);
    });
  });

  group('DailyUsageStore', () {
    late DailyUsageStore usage;
    final today = todayKey();

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      usage = DailyUsageStore(await SharedPreferences.getInstance());
    });

    test('counts entries until the server has counted them', () async {
      await usage.recordCreated(uid, today, TransactionType.income);
      await usage.recordCreated(uid, today, TransactionType.income);
      await usage.recordCreated(uid, today, TransactionType.expense);
      expect(
        usage.unsynced(uid, today),
        DailyUsage(day: today, income: 2, expense: 1),
      );

      await usage.recordUploaded(uid, today, TransactionType.income);
      expect(
        usage.unsynced(uid, today),
        DailyUsage(day: today, income: 1, expense: 1),
      );
    });

    test('never goes below zero', () async {
      await usage.recordUploaded(uid, today, TransactionType.expense);
      expect(usage.unsynced(uid, today), DailyUsage(day: today));
    });

    test('keeps users and days apart', () async {
      await usage.recordCreated(uid, today, TransactionType.income);
      expect(usage.unsynced('someone-else', today), DailyUsage(day: today));
      expect(
        usage.unsynced(uid, '2001-01-01'),
        const DailyUsage(day: '2001-01-01'),
      );
    });

    test('forgets days too old to upload', () async {
      await usage.recordCreated(uid, '2001-01-01', TransactionType.income);
      await usage.recordCreated(uid, today, TransactionType.income);
      expect(usage.unsynced(uid, '2001-01-01').income, 0);
      expect(usage.unsynced(uid, today).income, 1);
    });

    test('clear wipes one user', () async {
      await usage.recordCreated(uid, today, TransactionType.income);
      await usage.clear(uid);
      expect(usage.unsynced(uid, today), DailyUsage(day: today));
    });
  });

  group('upload', () {
    late Directory dir;
    late TransactionLocalStore store;
    late FakeFirebaseFirestore firestore;
    late DailyUsageStore usage;
    late OfflineTransactionRepository repo;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('hive_usage_test');
      Hive.init(dir.path);
      store = TransactionLocalStore();
      await store.open(uid);
      firestore = FakeFirebaseFirestore();
      SharedPreferences.setMockInitialValues({});
      usage = DailyUsageStore(await SharedPreferences.getInstance());
      final remote = TransactionRepository(firestore: firestore);
      repo = OfflineTransactionRepository(
        store: store,
        remote: remote,
        syncManager: SyncManager(
          store: store,
          repository: remote,
          connectivity: _Online(),
          usageStore: usage,
        ),
        usageStore: usage,
        autoSync: false,
      );
    });

    tearDown(() async {
      await store.close();
      await Hive.deleteFromDisk();
      await dir.delete(recursive: true);
    });

    Future<Map<String, dynamic>?> counter(String day) async =>
        (await firestore.doc(FirestorePaths.usageDay(uid, day)).get()).data();

    test('a new entry goes up with its day counter bump', () async {
      final saved = (await repo.addTransaction(
        newTx(TransactionType.income),
      )).when(success: (t) => t, failure: (_) => fail('not saved'));
      expect(
        saved.createdTzOffsetMinutes,
        DateTime.now().timeZoneOffset.inMinutes,
      );
      expect(
        usage.unsynced(uid, saved.usageDay).income,
        1,
        reason: 'counted on the device straight away',
      );

      await repo.syncManager.syncNow();

      final c = await counter(saved.usageDay);
      expect(c?['income'], 1);
      expect(c?['lastTxId'], saved.id);
      expect(
        usage.unsynced(uid, saved.usageDay).income,
        0,
        reason: 'the server count has taken over',
      );
      final doc = await firestore
          .doc(FirestorePaths.transaction(uid, saved.id))
          .get();
      expect(
        doc.data()?['createdTzOffsetMinutes'],
        saved.createdTzOffsetMinutes,
      );
    });

    test('editing an uploaded entry does not count again', () async {
      final saved = (await repo.addTransaction(
        newTx(TransactionType.expense),
      )).when(success: (t) => t, failure: (_) => fail('not saved'));
      await repo.syncManager.syncNow();

      await repo.updateTransaction(saved.copyWith(amount: 250));
      await repo.syncManager.syncNow();

      expect((await counter(saved.usageDay))?['expense'], 1);
    });

    test('deleting an entry before upload does not give it back', () async {
      final saved = (await repo.addTransaction(
        newTx(TransactionType.expense),
      )).when(success: (t) => t, failure: (_) => fail('not saved'));
      await repo.deleteTransaction(saved.id);
      expect(usage.unsynced(uid, saved.usageDay).expense, 1);
    });
  });
}
