import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:hive_ce/hive.dart';
import 'package:income_expense_tracker/core/constants/app_constants.dart';
import 'package:income_expense_tracker/data/local/transaction_local_store.dart';
import 'package:income_expense_tracker/models/budget_model.dart';
import 'package:income_expense_tracker/models/category_model.dart';
import 'package:income_expense_tracker/models/transaction_model.dart';

/// Shared builders and harnesses for the test suite.
///
/// Keeping construction in one place means a new required field on a model
/// breaks one file instead of twenty, which keeps the suite cheap to maintain
/// as the app grows.

const testUid = 'user-1';

/// A fixed "now" so date-boundary assertions never depend on the wall clock.
final fixedNow = DateTime(2026, 9, 15, 12, 0);

TransactionModel txFixture({
  String id = 'tx-1',
  TransactionType type = TransactionType.expense,
  double amount = 100,
  String categoryId = 'cat-food',
  String categoryName = 'Food',
  String? note = 'Lunch',
  DateTime? date,
  String? paymentMethod = 'Cash',
  DateTime? createdAt,
  DateTime? updatedAt,
}) {
  final when = date ?? fixedNow;
  return TransactionModel(
    id: id,
    type: type,
    amount: amount,
    categoryId: categoryId,
    categoryName: categoryName,
    note: note,
    date: when,
    paymentMethod: paymentMethod,
    createdAt: createdAt ?? when,
    updatedAt: updatedAt ?? when,
  );
}

CategoryModel categoryFixture({
  String id = 'cat-food',
  String name = 'Food',
  String icon = 'restaurant',
  int color = 0xFFEF6C00,
  TransactionType type = TransactionType.expense,
  bool isDefault = false,
  bool isArchived = false,
}) {
  return CategoryModel(
    id: id,
    name: name,
    icon: icon,
    color: color,
    type: type,
    isDefault: isDefault,
    isArchived: isArchived,
    createdAt: fixedNow,
  );
}

BudgetModel budgetFixture({
  String id = 'budget-1',
  String period = '2026-09',
  String? categoryId = 'cat-food',
  String? categoryName = 'Food',
  double limit = 5000,
  double alertThresholdPercent = 80,
}) {
  return BudgetModel(
    id: id,
    period: period,
    categoryId: categoryId,
    categoryName: categoryName,
    limit: limit,
    alertThresholdPercent: alertThresholdPercent,
    createdAt: fixedNow,
  );
}

/// Opens a real Hive box backed by a throwaway directory.
///
/// Hive is exercised for real rather than mocked: the persistence format is
/// exactly the thing a regression would break.
class HiveHarness {
  late Directory dir;
  late TransactionLocalStore store;

  Future<void> setUp({String uid = testUid}) async {
    dir = await Directory.systemTemp.createTemp('hive_test');
    Hive.init(dir.path);
    store = TransactionLocalStore();
    await store.open(uid);
  }

  Future<void> tearDown() async {
    await store.close();
    await Hive.deleteFromDisk();
    if (dir.existsSync()) await dir.delete(recursive: true);
  }
}

/// Seeds a fake Firestore collection with transactions.
Future<void> seedCloudTransactions(
  FakeFirebaseFirestore firestore,
  List<TransactionModel> items, {
  String uid = testUid,
}) async {
  for (final t in items) {
    await firestore
        .collection(FirestorePaths.transactions(uid))
        .doc(t.id)
        .set(t.toMap());
  }
}
