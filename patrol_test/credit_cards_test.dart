import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:income_expense_tracker/core/constants/app_constants.dart';
import 'package:patrol/patrol.dart';

import 'support/steps.dart';
import 'support/test_app.dart';

Future<void> _openCards(PatrolIntegrationTester $) async {
  await $.openSettings();
  await $('Credit cards').tap();
  await $(AppBar).$('Credit cards').waitUntilVisible();
}

/// A field on the card form, by the label the user reads.
PatrolFinder _field(PatrolIntegrationTester $, String label) =>
    $.sheet.$(TextField).containing(label);

Future<void> _addCard(
  PatrolIntegrationTester $, {
  required String name,
  String? last4,
  String? limit,
}) async {
  await $.typeInto(_field($, 'Card name'), name);
  if (last4 != null) {
    await $.typeInto(_field($, 'Last 4 digits (optional)'), last4);
  }
  if (limit != null) {
    await $.typeInto(_field($, 'Credit limit (optional)'), limit);
  }
  await $.tapInSheet(FilledButton);
}

void main() {
  patrolTest('a card is added with only its last four digits', ($) async {
    await launchSignedIn($);
    await _openCards($);
    await $('No credit cards yet').waitUntilVisible();

    await $(FilledButton).$('Add card').tap();
    await $('New credit card').waitUntilExists();

    // Pasting a full card number keeps only four digits.
    await $.typeInto(_field($, 'Last 4 digits (optional)'), '4111111111111111');
    expect($.sheet.$('4111'), findsOneWidget);

    await _addCard($, name: 'HDFC Millennia', last4: '4242', limit: '50000');

    await $('HDFC Millennia').waitUntilVisible();
    expect($('No credit cards yet'), findsNothing);
    expect($(FloatingActionButton).$('Add card'), findsOneWidget);
  });

  patrolTest('card spending is tracked separately from the cash balance', (
    $,
  ) async {
    final (backend, user) = await launchSignedIn($);
    await _openCards($);
    await $(FilledButton).$('Add card').tap();
    await _addCard($, name: 'Travel Card', last4: '1234');
    await $('Travel Card').waitUntilVisible();
    await $.goBack();
    await $.leaveSettings();

    await $.addTransaction(
      type: TransactionType.income,
      amount: 3000,
      category: 'Salary',
    );
    await $.addTransaction(
      type: TransactionType.expense,
      amount: 1200,
      category: 'Shopping',
      note: 'New shoes',
      payWithCard: 'Travel Card',
    );

    // The cash balance is untouched by the card swipe...
    await $(balance(3000)).waitUntilVisible();
    // ...and the card section reports the charge on its own.
    await $('Credit cards').scrollTo();
    expect($('${money(1200)} charged this month'), findsOneWidget);

    await $('New shoes').scrollTo();
    await $.eventually(() async {
      final cloud = await backend.cloudTransactions(user.uid);
      final shoes = cloud.where((t) => t.note == 'New shoes');
      return shoes.length == 1 &&
          shoes.single.paymentMethod == kCreditCardPaymentMethod &&
          shoes.single.creditCardId != null;
    }, reason: 'the expense is stored against the card');
  });

  patrolTest('a card can be renamed and deleted from its options menu', (
    $,
  ) async {
    await launchSignedIn($);
    await _openCards($);
    await $(FilledButton).$('Add card').tap();
    await _addCard($, name: 'Old Name');
    await $('Old Name').waitUntilVisible();

    await $(find.byTooltip('Card options')).tap();
    await $('Edit').tap();
    await $('Edit card').waitUntilExists();
    await _addCard($, name: 'Renamed Card');

    await $('Renamed Card').waitUntilVisible();
    expect($('Old Name'), findsNothing);

    await $(find.byTooltip('Card options')).tap();
    await $('Delete').tap();
    await $('Delete "Renamed Card"?').waitUntilVisible();
    await $.dialog.$('Delete').tap();

    await $('No credit cards yet').waitUntilVisible();
  });

  patrolTest('a card can be added from the payment method picker mid-expense', (
    $,
  ) async {
    await launchSignedIn($);

    await $(FloatingActionButton).$('Add').tap();
    await $.sheet.$('Expense').tap();
    await $.typeInto($.amountField, '499');
    await $.reveal($('Payment method'), scrollIn: $.transactionFormList);
    await $('Payment method').tap();
    await $.tapInSheet('Add your first credit card');

    await $('New credit card').waitUntilExists();
    await _addCard($, name: 'Amazon Pay');

    // Back on the expense form, already paying with the new card.
    await $('Add expense').waitUntilVisible();
    expect($('Amazon Pay'), findsOneWidget);

    await $(FilledButton).$('Add transaction').tap();
    await $('Transaction added').waitUntilVisible();
    await $('Credit cards').scrollTo();
    expect($('${money(499)} charged this month'), findsOneWidget);
  });
}
