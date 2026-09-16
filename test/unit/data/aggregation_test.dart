import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:income_expense_tracker/core/constants/app_constants.dart';
import 'package:income_expense_tracker/core/sync/sync_manager.dart';
import 'package:income_expense_tracker/data/repositories/offline_transaction_repository.dart';
import 'package:income_expense_tracker/data/repositories/transaction_repository.dart';

import '../../support/fixtures.dart';

/// The numbers behind the dashboard hero, the summary tiles, the donut,
/// Reports and Budgets all come from these two methods.
void main() {
  late HiveHarness hive;
  late OfflineTransactionRepository repo;

  final monthStart = DateTime(2026, 9, 1);
  final monthEnd = DateTime(2026, 9, 30, 23, 59, 59);

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

  test('empty ledger totals zero rather than throwing', () {
    final sums = repo.sumByType(start: monthStart, end: monthEnd);
    expect(sums[TransactionType.income], 0);
    expect(sums[TransactionType.expense], 0);
    expect(repo.categoryBreakdown(start: monthStart, end: monthEnd), isEmpty);
  });

  test('sums income and expenses separately', () async {
    await hive.store.putAll([
      txFixture(id: 'i1', type: TransactionType.income, amount: 5000),
      txFixture(id: 'e1', amount: 70),
      txFixture(id: 'e2', amount: 2000),
    ]);

    final sums = repo.sumByType(start: monthStart, end: monthEnd);

    expect(sums[TransactionType.income], 5000);
    expect(sums[TransactionType.expense], 2070);
  });

  group('date boundaries', () {
    test('includes transactions exactly on the start and end', () async {
      await hive.store.putAll([
        txFixture(id: 'start', amount: 10, date: monthStart),
        txFixture(id: 'end', amount: 20, date: monthEnd),
      ]);

      expect(repo.sumByType(start: monthStart, end: monthEnd)[
          TransactionType.expense], 30);
    });

    test('excludes the month either side', () async {
      await hive.store.putAll([
        txFixture(id: 'before', amount: 999, date: DateTime(2026, 8, 31, 23, 59)),
        txFixture(id: 'after', amount: 999, date: DateTime(2026, 10, 1)),
        txFixture(id: 'inside', amount: 10, date: DateTime(2026, 9, 15)),
      ]);

      expect(repo.sumByType(start: monthStart, end: monthEnd)[
          TransactionType.expense], 10);
    });
  });

  group('categoryBreakdown', () {
    test('groups by category name and adds them up', () async {
      await hive.store.putAll([
        txFixture(id: 'f1', categoryName: 'Food', amount: 70),
        txFixture(id: 'f2', categoryName: 'Food', amount: 75),
        txFixture(id: 'b1', categoryName: 'Bills', amount: 1170),
      ]);

      final breakdown =
          repo.categoryBreakdown(start: monthStart, end: monthEnd);

      expect(breakdown['Food'], 145);
      expect(breakdown['Bills'], 1170);
    });

    test('covers expenses by default and income on request', () async {
      await hive.store.putAll([
        txFixture(id: 'e', categoryName: 'Food', amount: 70),
        txFixture(
          id: 'i',
          type: TransactionType.income,
          categoryName: 'Salary',
          amount: 5000,
        ),
      ]);

      final expenses =
          repo.categoryBreakdown(start: monthStart, end: monthEnd);
      expect(expenses.keys, ['Food']);

      final income = repo.categoryBreakdown(
        start: monthStart,
        end: monthEnd,
        type: TransactionType.income,
      );
      expect(income.keys, ['Salary']);
    });

    test('respects the date window', () async {
      await hive.store.putAll([
        txFixture(id: 'old', categoryName: 'Food', amount: 500,
            date: DateTime(2026, 7, 1)),
        txFixture(id: 'new', categoryName: 'Food', amount: 70),
      ]);

      expect(repo.categoryBreakdown(start: monthStart, end: monthEnd)['Food'],
          70);
    });
  });

  test('a deleted transaction stops counting immediately', () async {
    await hive.store.putAll([txFixture(id: 'e1', amount: 100)]);
    expect(
        repo.sumByType(start: monthStart, end: monthEnd)[
            TransactionType.expense],
        100);

    await repo.deleteTransaction('e1');

    expect(
      repo.sumByType(start: monthStart, end: monthEnd)[
          TransactionType.expense],
      0,
      reason: 'tombstoned rows must not inflate the dashboard',
    );
  });
}
