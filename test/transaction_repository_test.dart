import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:income_expense_tracker/core/constants/app_constants.dart';
import 'package:income_expense_tracker/data/repositories/transaction_repository.dart';
import 'package:income_expense_tracker/models/transaction_model.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late TransactionRepository repo;
  const uid = 'test-user';

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repo = TransactionRepository(firestore: firestore);
  });

  TransactionModel buildTx({
    TransactionType type = TransactionType.expense,
    double amount = 100,
    DateTime? date,
  }) {
    final now = DateTime.now();
    return TransactionModel(
      id: '',
      type: type,
      amount: amount,
      categoryId: 'cat1',
      categoryName: 'Food',
      date: date ?? now,
      createdAt: now,
      updatedAt: now,
    );
  }

  test('addTransaction persists a document with a generated id', () async {
    final result = await repo.addTransaction(uid, buildTx());
    result.when(
      success: (tx) => expect(tx.id, isNotEmpty),
      failure: (f) => fail('Expected success, got $f'),
    );
  });

  test('sumByType correctly totals income and expenses within range', () async {
    final now = DateTime.now();
    await repo.addTransaction(uid, buildTx(type: TransactionType.income, amount: 1000, date: now));
    await repo.addTransaction(uid, buildTx(type: TransactionType.expense, amount: 250, date: now));
    await repo.addTransaction(uid, buildTx(type: TransactionType.expense, amount: 150, date: now));

    final result = await repo.sumByType(
      uid,
      start: now.subtract(const Duration(days: 1)),
      end: now.add(const Duration(days: 1)),
    );

    result.when(
      success: (sums) {
        expect(sums[TransactionType.income], 1000);
        expect(sums[TransactionType.expense], 400);
      },
      failure: (f) => fail('Expected success, got $f'),
    );
  });

  test('deleteTransaction removes the document', () async {
    final added = await repo.addTransaction(uid, buildTx());
    final id = added.when(success: (tx) => tx.id, failure: (_) => '');

    final deleteResult = await repo.deleteTransaction(uid, id);
    expect(deleteResult.isSuccess, isTrue);

    final page = await repo.fetchPage(uid: uid);
    page.when(
      success: (list) => expect(list.where((t) => t.id == id), isEmpty),
      failure: (f) => fail('Expected success, got $f'),
    );
  });

  test('categoryBreakdown groups expense totals by category name', () async {
    final now = DateTime.now();
    await repo.addTransaction(
      uid,
      buildTx(type: TransactionType.expense, amount: 50, date: now)
          .copyWith(categoryName: 'Food'),
    );
    await repo.addTransaction(
      uid,
      buildTx(type: TransactionType.expense, amount: 30, date: now)
          .copyWith(categoryName: 'Food'),
    );
    await repo.addTransaction(
      uid,
      buildTx(type: TransactionType.expense, amount: 20, date: now)
          .copyWith(categoryName: 'Transport'),
    );

    final result = await repo.categoryBreakdown(
      uid,
      start: now.subtract(const Duration(days: 1)),
      end: now.add(const Duration(days: 1)),
    );

    result.when(
      success: (breakdown) {
        expect(breakdown['Food'], 80);
        expect(breakdown['Transport'], 20);
      },
      failure: (f) => fail('Expected success, got $f'),
    );
  });
}
