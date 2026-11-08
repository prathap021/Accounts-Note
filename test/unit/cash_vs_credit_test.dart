import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:accounts_note/core/constants/app_constants.dart';
import 'package:accounts_note/core/sync/sync_manager.dart';
import 'package:accounts_note/data/repositories/offline_transaction_repository.dart';
import 'package:accounts_note/data/repositories/transaction_repository.dart';
import 'package:accounts_note/providers/dashboard_provider.dart';

import '../support/fixtures.dart';

/// Swiping a credit card moves none of the user's own money — the issuer pays
/// the merchant and bills later. So a card charge must not come off the
/// available balance, must not count as a cash expense, and must not be
/// carried forward as a shortfall. It is tracked against the card instead.
///
/// Getting this wrong is not a cosmetic bug: it makes the balance read low by
/// the whole card bill, every month.
void main() {
  late HiveHarness hive;
  late OfflineTransactionRepository repo;

  final card = creditCardFixture(id: 'card-1', creditLimit: 50000);
  final sept = DateTime(2026, 9, 15, 10, 0);
  final octoberNow = DateTime(2026, 10, 15, 10, 0);
  final septemberNow = DateTime(2026, 9, 20, 10, 0);

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

  group('the available balance', () {
    test('is untouched by a card charge', () async {
      await hive.store.putAll([
        txFixture(
          id: 'salary',
          type: TransactionType.income,
          amount: 30000,
          date: sept,
        ),
        cardTxFixture(card, id: 'swipe', amount: 8000, date: sept),
      ]);

      final summary = summaryAt(septemberNow);
      expect(summary.totalIncome, 30000);
      expect(summary.totalExpense, 0, reason: 'nothing was paid in cash');
      expect(summary.balance, 30000, reason: 'the ₹8,000 is debt, not cash');
      expect(summary.creditCardSpend, 8000);
    });

    test('still drops for a cash expense', () async {
      await hive.store.putAll([
        txFixture(
          id: 'salary',
          type: TransactionType.income,
          amount: 30000,
          date: sept,
        ),
        txFixture(id: 'rent', amount: 12000, date: sept),
      ]);

      final summary = summaryAt(septemberNow);
      expect(summary.totalExpense, 12000);
      expect(summary.balance, 18000);
      expect(summary.creditCardSpend, 0);
    });

    test('separates the two when both are present', () async {
      await hive.store.putAll([
        txFixture(
          id: 'salary',
          type: TransactionType.income,
          amount: 30000,
          date: sept,
        ),
        txFixture(id: 'rent', amount: 12000, date: sept),
        cardTxFixture(card, id: 'swipe', amount: 8000, date: sept),
      ]);

      final summary = summaryAt(septemberNow);
      expect(summary.totalExpense, 12000);
      expect(summary.creditCardSpend, 8000);
      expect(summary.balance, 18000);
    });
  });

  group('carry forward', () {
    test('does not carry a card charge into the next month', () async {
      await hive.store.putAll([
        txFixture(
          id: 'salary',
          type: TransactionType.income,
          amount: 30000,
          date: sept,
        ),
        cardTxFixture(card, id: 'swipe', amount: 8000, date: sept),
      ]);

      // October opens with September's cash, not cash minus the card bill.
      final october = summaryAt(octoberNow);
      expect(october.carriedForward, 30000);
      expect(october.balance, 30000);
    });

    test('carries a cash shortfall as before', () async {
      await hive.store.putAll([
        txFixture(
          id: 'salary',
          type: TransactionType.income,
          amount: 10000,
          date: sept,
        ),
        txFixture(id: 'rent', amount: 12000, date: sept),
      ]);

      expect(summaryAt(octoberNow).carriedForward, -2000);
    });
  });

  group('the category breakdown', () {
    test('leaves card spending out, matching the expense card above it',
        () async {
      await hive.store.putAll([
        txFixture(
          id: 'groceries',
          amount: 2000,
          categoryName: 'Food',
          date: sept,
        ),
        cardTxFixture(
          card,
          id: 'dinner',
          amount: 3000,
          categoryName: 'Food',
          date: sept,
        ),
      ]);

      final summary = summaryAt(septemberNow);
      // The donut sits under "Expenses", so it has to total the same 2,000 —
      // a 5,000 slice beside a 2,000 card would not add up.
      expect(summary.expenseByCategory['Food'], 2000);
      expect(summary.totalExpense, 2000);
    });
  });

  group('creditCardSpend', () {
    test('counts only expenses, not a refund to the card', () async {
      await hive.store.putAll([
        cardTxFixture(card, id: 'buy', amount: 5000, date: sept),
        cardTxFixture(
          card,
          id: 'refund',
          type: TransactionType.income,
          amount: 1500,
          date: sept,
        ),
      ]);

      expect(summaryAt(septemberNow).creditCardSpend, 5000);
    });

    test('is scoped to the month on screen', () async {
      await hive.store.putAll([
        cardTxFixture(card, id: 'sept', amount: 5000, date: sept),
        cardTxFixture(
          card,
          id: 'oct',
          amount: 700,
          date: DateTime(2026, 10, 3, 10, 0),
        ),
      ]);

      expect(summaryAt(septemberNow).creditCardSpend, 5000);
      expect(summaryAt(octoberNow).creditCardSpend, 700);
    });

    test('is zero with no cards in play', () async {
      await hive.store.putAll([txFixture(id: 'cash', amount: 100, date: sept)]);
      expect(summaryAt(septemberNow).creditCardSpend, 0);
    });
  });

  group('other screens are unaffected', () {
    test('reports and budgets still total every expense', () async {
      await hive.store.putAll([
        txFixture(id: 'cash', amount: 2000, date: sept),
        cardTxFixture(card, id: 'swipe', amount: 3000, date: sept),
      ]);

      // cashOnly defaults to false, so nothing outside the dashboard changed
      // behaviour when the flag was introduced.
      final all = repo.sumByType(
        start: DateTime(2026, 9, 1),
        end: DateTime(2026, 9, 30, 23, 59, 59),
      );
      expect(all[TransactionType.expense], 5000);
    });
  });
}
