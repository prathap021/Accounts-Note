import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:income_expense_tracker/core/constants/app_constants.dart';
import 'package:income_expense_tracker/core/sync/sync_manager.dart';
import 'package:income_expense_tracker/data/repositories/offline_transaction_repository.dart';
import 'package:income_expense_tracker/data/repositories/transaction_repository.dart';

import '../../support/fixtures.dart';

/// Covers the Activity screen's filter flow. These run against the real local
/// store, so they also prove filtering works with no network.
void main() {
  late HiveHarness hive;
  late OfflineTransactionRepository repo;

  setUp(() async {
    hive = HiveHarness();
    await hive.setUp();
    repo = OfflineTransactionRepository(
      store: hive.store,
      remote: TransactionRepository(firestore: FakeFirebaseFirestore()),
      syncManager: SyncManager(
        store: hive.store,
        repository: TransactionRepository(firestore: FakeFirebaseFirestore()),
      ),
      autoSync: false,
    );

    await hive.store.putAll([
      txFixture(
        id: 'a',
        categoryId: 'cat-food',
        categoryName: 'Food',
        note: 'Lunch with team',
        amount: 70,
        paymentMethod: 'Cash',
        date: DateTime(2026, 9, 15),
      ),
      txFixture(
        id: 'b',
        type: TransactionType.income,
        categoryId: 'cat-salary',
        categoryName: 'Salary',
        note: 'Monthly payout',
        amount: 5000,
        paymentMethod: 'Bank Transfer',
        date: DateTime(2026, 9, 10),
      ),
      txFixture(
        id: 'c',
        categoryId: 'cat-bills',
        categoryName: 'Bills',
        note: 'Train ticket',
        amount: 70,
        paymentMethod: 'UPI',
        date: DateTime(2026, 8, 20),
      ),
    ]);
  });

  tearDown(() => hive.tearDown());

  Future<List<String>> idsFor(TransactionFilter filter) async {
    final items = await repo.watchTransactions(filter: filter).first;
    return items.map((t) => t.id).toList();
  }

  test('no filter returns everything, newest first', () async {
    expect(await idsFor(const TransactionFilter()), ['a', 'b', 'c']);
  });

  test('filters by type', () async {
    expect(
      await idsFor(const TransactionFilter(type: TransactionType.income)),
      ['b'],
    );
    expect(
      await idsFor(const TransactionFilter(type: TransactionType.expense)),
      ['a', 'c'],
    );
  });

  test('filters by category', () async {
    expect(
      await idsFor(const TransactionFilter(categoryId: 'cat-bills')),
      ['c'],
    );
  });

  test('filters by payment method', () async {
    expect(await idsFor(const TransactionFilter(paymentMethod: 'UPI')), ['c']);
  });

  group('date range', () {
    test('includes both endpoints', () async {
      final ids = await idsFor(TransactionFilter(
        startDate: DateTime(2026, 9, 10),
        endDate: DateTime(2026, 9, 15),
      ));
      expect(ids, ['a', 'b']);
    });

    test('excludes anything outside it', () async {
      final ids = await idsFor(TransactionFilter(
        startDate: DateTime(2026, 9, 1),
        endDate: DateTime(2026, 9, 30),
      ));
      expect(ids, isNot(contains('c')));
    });
  });

  group('search', () {
    test('matches the category name, case-insensitively', () async {
      expect(await idsFor(const TransactionFilter(searchQuery: 'food')), ['a']);
      expect(await idsFor(const TransactionFilter(searchQuery: 'FOOD')), ['a']);
    });

    test('matches the note', () async {
      expect(
          await idsFor(const TransactionFilter(searchQuery: 'train')), ['c']);
    });

    test('matches the payment method', () async {
      expect(await idsFor(const TransactionFilter(searchQuery: 'upi')), ['c']);
    });

    test('ignores surrounding whitespace', () async {
      expect(
          await idsFor(const TransactionFilter(searchQuery: '  lunch  ')), ['a']);
    });

    test('returns nothing when there is no match', () async {
      expect(await idsFor(const TransactionFilter(searchQuery: 'zzz')), isEmpty);
    });

    test('an empty query is treated as no filter', () async {
      expect(await idsFor(const TransactionFilter(searchQuery: '')),
          ['a', 'b', 'c']);
    });
  });

  test('filters combine (AND, not OR)', () async {
    final ids = await idsFor(const TransactionFilter(
      type: TransactionType.expense,
      searchQuery: 'ticket',
    ));
    expect(ids, ['c']);

    final none = await idsFor(const TransactionFilter(
      type: TransactionType.income,
      searchQuery: 'ticket',
    ));
    expect(none, isEmpty);
  });

  test('tombstoned records never appear in results', () async {
    await repo.deleteTransaction('a');
    expect(await idsFor(const TransactionFilter()), ['b', 'c']);
  });
}
