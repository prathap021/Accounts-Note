import 'package:flutter_test/flutter_test.dart';
import 'package:income_expense_tracker/core/constants/app_constants.dart';
import 'package:income_expense_tracker/core/utils/currency_formatter.dart';
import 'package:income_expense_tracker/models/transaction_model.dart';

void main() {
  group('CurrencyFormatter', () {
    test('formats INR with the rupee symbol', () {
      final formatted = CurrencyFormatter.format(1234.5, currencyCode: 'INR');
      expect(formatted, contains('₹'));
    });

    test('formats USD with the dollar symbol', () {
      final formatted = CurrencyFormatter.format(99.99, currencyCode: 'USD');
      expect(formatted, contains('\$'));
    });
  });

  group('TransactionModel', () {
    test('toMap/fromDoc round trip preserves core fields', () {
      final now = DateTime.now();
      final tx = TransactionModel(
        id: 'abc',
        type: TransactionType.income,
        amount: 500,
        categoryId: 'cat1',
        categoryName: 'Salary',
        date: now,
        createdAt: now,
        updatedAt: now,
      );
      final map = tx.toMap();
      expect(map['amount'], 500);
      expect(map['type'], 'income');
      expect(map['categoryName'], 'Salary');
    });

    test('copyWith overrides only the specified fields', () {
      final now = DateTime.now();
      final tx = TransactionModel(
        id: 'abc',
        type: TransactionType.expense,
        amount: 100,
        categoryId: 'cat1',
        categoryName: 'Food',
        date: now,
        createdAt: now,
        updatedAt: now,
      );
      final updated = tx.copyWith(amount: 200);
      expect(updated.amount, 200);
      expect(updated.categoryName, 'Food');
    });
  });
}
