import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:income_expense_tracker/core/constants/app_constants.dart';
import 'package:income_expense_tracker/core/sync/sync_manager.dart';
import 'package:income_expense_tracker/data/repositories/offline_transaction_repository.dart';
import 'package:income_expense_tracker/data/repositories/transaction_repository.dart';
import 'package:income_expense_tracker/providers/dashboard_provider.dart';

import '../support/fixtures.dart';

/// The balance must not reset on the 1st of the month.
///
/// The dashboard used to total only the current month, so ₹30,000 earned and
/// ₹25,000 spent in September showed as a ₹0 balance on October 1st — the
/// ₹5,000 left over simply vanished.
void main() {
  late HiveHarness hive;
  late OfflineTransactionRepository repo;

  final october1 = DateTime(2026, 10, 1, 9, 0);

  setUp(() async {
    hive = HiveHarness();
    await hive.setUp();
    final firestore = FakeFirebaseFirestore();
    repo = OfflineTransactionRepository(
      store: hive.store,
      remote: TransactionRepository(firestore: firestore),
      syncManager: SyncManager(
        store: hive.store,
        repository: TransactionRepository(firestore: firestore),
      ),
      autoSync: false,
    );
  });

  tearDown(() => hive.tearDown());

  DashboardSummary summaryAt(DateTime now) =>
      buildDashboardSummary(repo, now: now);

  test('last month\'s leftover opens the new month', () async {
    await hive.store.putAll([
      txFixture(
        id: 'sep-salary',
        type: TransactionType.income,
        amount: 30000,
        date: DateTime(2026, 9, 1),
      ),
      txFixture(id: 'sep-spend', amount: 25000, date: DateTime(2026, 9, 20)),
    ]);

    final s = summaryAt(october1);

    expect(s.carriedForward, 5000);
    expect(s.balance, 5000, reason: 'the ₹5,000 must not reset to zero');
    expect(s.totalIncome, 0, reason: 'income tile still means this month');
    expect(s.totalExpense, 0);
  });

  test('new income adds to what was carried over', () async {
    await hive.store.putAll([
      txFixture(
        id: 'sep-salary',
        type: TransactionType.income,
        amount: 30000,
        date: DateTime(2026, 9, 1),
      ),
      txFixture(id: 'sep-spend', amount: 25000, date: DateTime(2026, 9, 20)),
      txFixture(
        id: 'oct-salary',
        type: TransactionType.income,
        amount: 30000,
        date: october1,
      ),
      txFixture(id: 'oct-spend', amount: 2000, date: october1),
    ]);

    final s = summaryAt(october1);

    expect(s.totalIncome, 30000);
    expect(s.totalExpense, 2000);
    expect(s.carriedForward, 5000);
    expect(s.balance, 33000);
  });

  test('leftovers accumulate across several months', () async {
    await hive.store.putAll([
      txFixture(
        id: 'aug-in',
        type: TransactionType.income,
        amount: 20000,
        date: DateTime(2026, 8, 1),
      ),
      txFixture(id: 'aug-out', amount: 17000, date: DateTime(2026, 8, 15)),
      txFixture(
        id: 'sep-in',
        type: TransactionType.income,
        amount: 30000,
        date: DateTime(2026, 9, 1),
      ),
      txFixture(id: 'sep-out', amount: 25000, date: DateTime(2026, 9, 15)),
    ]);

    expect(summaryAt(DateTime(2026, 9, 10)).carriedForward, 3000);
    expect(summaryAt(october1).carriedForward, 8000);
  });

  test('an overspent month carries a shortfall, not zero', () async {
    await hive.store.putAll([
      txFixture(
        id: 'sep-in',
        type: TransactionType.income,
        amount: 30000,
        date: DateTime(2026, 9, 1),
      ),
      txFixture(id: 'sep-out', amount: 32000, date: DateTime(2026, 9, 15)),
      txFixture(
        id: 'oct-in',
        type: TransactionType.income,
        amount: 30000,
        date: october1,
      ),
    ]);

    final s = summaryAt(october1);

    expect(s.carriedForward, -2000);
    expect(s.balance, 28000);
  });

  test('the first month has nothing to carry', () async {
    await hive.store.putAll([
      txFixture(
        id: 'in',
        type: TransactionType.income,
        amount: 30000,
        date: october1,
      ),
    ]);

    final s = summaryAt(october1);

    expect(s.carriedForward, 0);
    expect(s.balance, 30000);
  });

  test('fixing an old transaction corrects the carry-over', () async {
    await hive.store.putAll([
      txFixture(
        id: 'sep-in',
        type: TransactionType.income,
        amount: 30000,
        date: DateTime(2026, 9, 1),
      ),
      txFixture(id: 'sep-out', amount: 25000, date: DateTime(2026, 9, 15)),
    ]);
    expect(summaryAt(october1).carriedForward, 5000);

    final edited = hive.store.getById('sep-out')!.copyWith(amount: 20000);
    await repo.updateTransaction(edited);
    expect(summaryAt(october1).carriedForward, 10000);

    await repo.deleteTransaction('sep-out');
    expect(summaryAt(october1).carriedForward, 30000,
        reason: 'a tombstoned row must stop counting immediately');
  });

  group('month boundary', () {
    test('midnight on the 1st belongs to the new month', () async {
      await hive.store.putAll([
        txFixture(
          id: 'last-second',
          type: TransactionType.income,
          amount: 100,
          date: DateTime(2026, 9, 30, 23, 59, 59),
        ),
        txFixture(
          id: 'midnight',
          type: TransactionType.income,
          amount: 7,
          date: DateTime(2026, 10, 1),
        ),
      ]);

      final s = summaryAt(october1);

      expect(s.carriedForward, 100);
      expect(s.totalIncome, 7);
      expect(s.balance, 107);
    });

    test('later months never leak into the carry-over', () async {
      await hive.store.putAll([
        txFixture(
          id: 'nov',
          type: TransactionType.income,
          amount: 999,
          date: DateTime(2026, 11, 1),
        ),
      ]);

      final s = summaryAt(october1);

      expect(s.carriedForward, 0);
      expect(s.balance, 0);
    });
  });
}
