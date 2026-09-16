import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:income_expense_tracker/core/constants/app_constants.dart';
import 'package:income_expense_tracker/data/repositories/category_repository.dart';

import '../../support/fixtures.dart';

/// Categories drive the pickers, the Activity row icons and the donut legend.
void main() {
  late FakeFirebaseFirestore firestore;
  late CategoryRepository repo;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repo = CategoryRepository(firestore: firestore);
  });

  Future<String> addCategory({
    String name = 'Food',
    TransactionType type = TransactionType.expense,
    bool isDefault = false,
  }) async {
    final result = await repo.addCategory(
      testUid,
      categoryFixture(name: name, type: type, isDefault: isDefault),
    );
    return result.when(success: (c) => c.id, failure: (f) => throw StateError(f.message));
  }

  test('adds a category and returns it with its generated id', () async {
    final result =
        await repo.addCategory(testUid, categoryFixture(name: 'Travel'));

    final created =
        result.when(success: (c) => c, failure: (_) => null);
    expect(created, isNotNull);
    expect(created!.id, isNotEmpty);
    expect(created.name, 'Travel');
  });

  test('watch returns only the requested type', () async {
    await addCategory(name: 'Food');
    await addCategory(name: 'Salary', type: TransactionType.income);

    final expenses =
        await repo.watchCategories(testUid, type: TransactionType.expense).first;
    final income =
        await repo.watchCategories(testUid, type: TransactionType.income).first;

    expect(expenses.map((c) => c.name), ['Food']);
    expect(income.map((c) => c.name), ['Salary']);
  });

  test('watch with no type returns every category', () async {
    await addCategory(name: 'Food');
    await addCategory(name: 'Salary', type: TransactionType.income);

    final all = await repo.watchCategories(testUid).first;

    expect(all, hasLength(2));
  });

  test('categories come back alphabetically', () async {
    await addCategory(name: 'Travel');
    await addCategory(name: 'Bills');
    await addCategory(name: 'Food');

    final all = await repo.watchCategories(testUid).first;

    expect(all.map((c) => c.name), ['Bills', 'Food', 'Travel']);
  });

  test('updating a category changes it in place', () async {
    final id = await addCategory(name: 'Food');
    final existing = (await repo.watchCategories(testUid).first).single;

    await repo.updateCategory(testUid, existing.copyWith(name: 'Groceries'));

    final all = await repo.watchCategories(testUid).first;
    expect(all, hasLength(1));
    expect(all.single.name, 'Groceries');
    expect(all.single.id, id);
  });

  group('removal', () {
    test('a custom category with no history is deleted outright', () async {
      await addCategory(name: 'Temp');
      final category = (await repo.watchCategories(testUid).first).single;

      await repo.deleteOrArchiveCategory(testUid, category,
          hasTransactions: false);

      final snap = await firestore
          .collection(FirestorePaths.categories(testUid))
          .get();
      expect(snap.docs, isEmpty);
    });

    test('a category with history is archived, preserving past records',
        () async {
      await addCategory(name: 'Food');
      final category = (await repo.watchCategories(testUid).first).single;

      await repo.deleteOrArchiveCategory(testUid, category,
          hasTransactions: true);

      final snap = await firestore
          .collection(FirestorePaths.categories(testUid))
          .get();
      expect(snap.docs, hasLength(1), reason: 'the document survives');
      expect(snap.docs.single.data()['isArchived'], isTrue);
    });

    test('a default category is archived even with no history', () async {
      await addCategory(name: 'Other', isDefault: true);
      final category = (await repo.watchCategories(testUid).first).single;

      await repo.deleteOrArchiveCategory(testUid, category,
          hasTransactions: false);

      final snap = await firestore
          .collection(FirestorePaths.categories(testUid))
          .get();
      expect(snap.docs.single.data()['isArchived'], isTrue);
    });

    test('archived categories disappear from the pickers', () async {
      await addCategory(name: 'Food');
      final category = (await repo.watchCategories(testUid).first).single;
      await repo.deleteOrArchiveCategory(testUid, category,
          hasTransactions: true);

      expect(await repo.watchCategories(testUid).first, isEmpty);
    });
  });

  test('one user cannot see another user\'s categories', () async {
    await addCategory(name: 'Mine');

    expect(await repo.watchCategories('someone-else').first, isEmpty);
  });
}
