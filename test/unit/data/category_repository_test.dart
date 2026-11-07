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
    test('a category is deleted outright', () async {
      await addCategory(name: 'Temp');
      final category = (await repo.watchCategories(testUid).first).single;

      await repo.deleteCategory(testUid, category.id);

      final snap = await firestore
          .collection(FirestorePaths.categories(testUid))
          .get();
      expect(snap.docs, isEmpty);
    });

    test('the fallback "Other" is found, and un-hidden if archived', () async {
      final id = await addCategory(name: 'Other', isDefault: true);
      await firestore
          .doc(FirestorePaths.category(testUid, id))
          .update({'isArchived': true});

      final other = (await repo.findOrCreateFallback(
        testUid,
        TransactionType.expense,
      )).when(success: (c) => c, failure: (_) => fail('no fallback'));
      expect(other.id, id);
      final doc =
          await firestore.doc(FirestorePaths.category(testUid, id)).get();
      expect(doc.data()!['isArchived'], isFalse);
    });

    test('a missing "Other" is created for the right type', () async {
      final other = (await repo.findOrCreateFallback(
        testUid,
        TransactionType.income,
      )).when(success: (c) => c, failure: (_) => fail('no fallback'));
      expect(other.name, 'Other');
      expect(other.type, TransactionType.income);
      expect(await repo.watchCategories(testUid).first, hasLength(1));
    });
  });

  test('one user cannot see another user\'s categories', () async {
    await addCategory(name: 'Mine');

    expect(await repo.watchCategories('someone-else').first, isEmpty);
  });
}
