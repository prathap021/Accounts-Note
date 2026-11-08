import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:accounts_note/core/constants/app_constants.dart';
import 'package:accounts_note/core/sync/sync_manager.dart';
import 'package:accounts_note/data/repositories/offline_transaction_repository.dart';
import 'package:accounts_note/data/repositories/transaction_repository.dart';

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

  group('credit cards', () {
    final hdfc = creditCardFixture();
    final sbi = creditCardFixture(
      id: 'card-sbi',
      name: 'SBI SimplyClick',
      last4: '9876',
    );

    setUp(() async {
      await hive.store.putAll([
        cardTxFixture(hdfc, id: 'h1', amount: 1200, date: DateTime(2026, 9, 14)),
        cardTxFixture(sbi, id: 's1', amount: 300, date: DateTime(2026, 9, 13)),
      ]);
    });

    test('one card shows only what was charged to it', () async {
      expect(
        await idsFor(const TransactionFilter(creditCardId: 'card-hdfc')),
        ['h1'],
      );
    });

    test('"All cards" covers every card and nothing paid another way',
        () async {
      expect(
        await idsFor(
          const TransactionFilter(paymentMethod: kCreditCardPaymentMethod),
        ),
        ['h1', 's1'],
      );
    });

    test("search finds a card's entries by its name or last four digits",
        () async {
      expect(await idsFor(const TransactionFilter(searchQuery: 'millennia')),
          ['h1']);
      expect(await idsFor(const TransactionFilter(searchQuery: '9876')), ['s1']);
    });

    test('a card filter combines with the others', () async {
      final ids = await idsFor(TransactionFilter(
        creditCardId: 'card-hdfc',
        startDate: DateTime(2026, 9, 15),
        endDate: DateTime(2026, 9, 30),
      ));
      expect(ids, isEmpty, reason: 'the HDFC charge is dated the 14th');
    });

    test('a card filter alone counts as filtering', () {
      expect(const TransactionFilter(creditCardId: 'card-hdfc').isEmpty, isFalse,
          reason: 'otherwise Activity hides the chip and the total');
    });

    test('matches agrees with the list, entry by entry', () async {
      // The filter sheet totals its selection with matches(); Activity lists
      // it through the repository. They must pick the same entries.
      const filter = TransactionFilter(
        type: TransactionType.expense,
        paymentMethod: kCreditCardPaymentMethod,
      );
      final viaMatches =
          hive.store.getAll().where(filter.matches).map((t) => t.id);

      expect(await idsFor(filter), viaMatches.toList());
    });
  });
}
