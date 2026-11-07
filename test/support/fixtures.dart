import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:hive_ce/hive.dart';
import 'package:income_expense_tracker/core/constants/app_constants.dart';
import 'package:income_expense_tracker/data/local/transaction_local_store.dart';
import 'package:income_expense_tracker/models/budget_model.dart';
import 'package:income_expense_tracker/models/category_model.dart';
import 'package:income_expense_tracker/models/credit_card_model.dart';
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
  String? creditCardId,
  String? creditCardName,
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
    creditCardId: creditCardId,
    creditCardName: creditCardName,
    createdAt: createdAt ?? when,
    updatedAt: updatedAt ?? when,
  );
}

/// A transaction charged to [card], set up the way the expense form saves
/// one: the credit-card payment method, the card's id and its display name.
TransactionModel cardTxFixture(
  CreditCardModel card, {
  String id = 'tx-card',
  TransactionType type = TransactionType.expense,
  double amount = 100,
  String categoryId = 'cat-food',
  String categoryName = 'Food',
  String? note,
  DateTime? date,
}) {
  return txFixture(
    id: id,
    type: type,
    amount: amount,
    categoryId: categoryId,
    categoryName: categoryName,
    note: note,
    date: date,
    paymentMethod: kCreditCardPaymentMethod,
    creditCardId: card.id,
    creditCardName: card.displayName,
  );
}

CreditCardModel creditCardFixture({
  String id = 'card-hdfc',
  String name = 'HDFC Millennia',
  String? last4 = '4321',
  int color = 0xFF1E3A8A,
  double? creditLimit,
}) {
  return CreditCardModel(
    id: id,
    name: name,
    last4: last4,
    color: color,
    creditLimit: creditLimit,
    createdAt: fixedNow,
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
