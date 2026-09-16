import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:income_expense_tracker/core/constants/app_constants.dart';
import 'package:income_expense_tracker/data/repositories/budget_repository.dart';

import '../../support/fixtures.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late BudgetRepository repo;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repo = BudgetRepository(firestore: firestore);
  });

  test('saves a budget and reads it back for the period', () async {
    await repo.setBudget(testUid, budgetFixture(limit: 5000));

    final budgets = await repo.watchBudgets(testUid, '2026-09').first;

    expect(budgets, hasLength(1));
    expect(budgets.single.limit, 5000);
    expect(budgets.single.categoryName, 'Food');
  });

  test('re-saving the same category and period updates instead of duplicating',
      () async {
    await repo.setBudget(testUid, budgetFixture(limit: 5000));
    await repo.setBudget(testUid, budgetFixture(limit: 8000));

    final budgets = await repo.watchBudgets(testUid, '2026-09').first;

    expect(budgets, hasLength(1), reason: 'deterministic doc id per period');
    expect(budgets.single.limit, 8000);
  });

  test('an overall budget coexists with a per-category one', () async {
    await repo.setBudget(testUid, budgetFixture(limit: 5000));
    await repo.setBudget(
      testUid,
      budgetFixture(categoryId: null, categoryName: null, limit: 20000),
    );

    final budgets = await repo.watchBudgets(testUid, '2026-09').first;

    expect(budgets, hasLength(2));
    expect(
      budgets.where((b) => b.categoryId == null).single.limit,
      20000,
    );
  });

  test('budgets are scoped to their period', () async {
    await repo.setBudget(testUid, budgetFixture(period: '2026-09'));
    await repo.setBudget(testUid, budgetFixture(period: '2026-10'));

    expect(await repo.watchBudgets(testUid, '2026-09').first, hasLength(1));
    expect(await repo.watchBudgets(testUid, '2026-11').first, isEmpty);
  });

  test('deleting removes the budget', () async {
    await repo.setBudget(testUid, budgetFixture());
    final saved = (await repo.watchBudgets(testUid, '2026-09').first).single;

    await repo.deleteBudget(testUid, saved.id);

    expect(await repo.watchBudgets(testUid, '2026-09').first, isEmpty);
  });

  test('the alert threshold round-trips, defaulting to 80', () async {
    await repo.setBudget(testUid, budgetFixture(alertThresholdPercent: 65));
    expect(
      (await repo.watchBudgets(testUid, '2026-09').first).single
          .alertThresholdPercent,
      65,
    );

    await firestore
        .collection(FirestorePaths.budgets(testUid))
        .doc('2026-09_no-threshold')
        .set({
      'period': '2026-09',
      'categoryId': 'x',
      'limit': 100,
    });

    final all = await repo.watchBudgets(testUid, '2026-09').first;
    final legacy = all.firstWhere((b) => b.categoryId == 'x');
    expect(legacy.alertThresholdPercent, 80);
  });

  test('one user cannot see another user\'s budgets', () async {
    await repo.setBudget(testUid, budgetFixture());
    expect(await repo.watchBudgets('someone-else', '2026-09').first, isEmpty);
  });
}
