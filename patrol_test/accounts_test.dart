import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:accounts_note/core/constants/app_constants.dart';
import 'package:patrol/patrol.dart';

import 'support/steps.dart';
import 'support/test_app.dart';

/// Cash, bank, UPI and wallet accounts, and transfers between them.
void main() {
  Future<void> openAccounts(PatrolIntegrationTester $) async {
    await $.openSettings();
    final tile = $('Accounts');
    await $.reveal(tile, scrollIn: find.byType(Scrollable).first);
    await tile.tap();
  }

  Future<void> fillAccount(
    PatrolIntegrationTester $, {
    required String name,
    String? kind,
    String? opening,
  }) async {
    await $('New account').waitUntilVisible();
    if (kind != null) await $.sheet.$(ChoiceChip).containing(kind).tap();
    await $.typeInto($(const Key('account-name')), name);
    if (opening != null) {
      await $.typeInto($(const Key('account-opening')), opening);
    }
    await $.tapInSheet(find.widgetWithText(FilledButton, 'Add account'));
    await $(name).waitUntilVisible();
  }

  patrolTest(
    'accounts start from their opening balance, and a transfer moves money '
    'between them without changing the total',
    ($) async {
      await launchSignedIn($);
      await openAccounts($);
      await $('No accounts yet').waitUntilVisible();
      await $(FilledButton).$('Add account').tap();
      await fillAccount($, name: 'SBI savings', opening: '10000');

      await $(FloatingActionButton).$('Add account').tap();
      await fillAccount($, name: 'Cash in hand', kind: 'Cash');
      expect($(const Key('accounts-total')).$(money(10000)), findsOneWidget);

      await $(FilledButton).$('Transfer').tap();
      await $('Transfer money').waitUntilVisible();
      await $.typeInto($(const Key('transfer-amount')), '2000');
      await $.tapInSheet(find.widgetWithText(FilledButton, 'Move money'));
      await $('Moved ${money(2000)} to Cash in hand').waitUntilVisible();
      await $.dismissSnackBars();

      await $('SBI savings → Cash in hand').waitUntilVisible();
      expect($(ListTile).containing('SBI savings').$(money(8000)), findsOne);
      expect(
        $(ListTile).containing('Cash in hand').$(money(2000)),
        findsWidgets,
      );
      expect(
        $(const Key('accounts-total')).$(money(10000)),
        findsOneWidget,
        reason: 'a transfer is not income or an expense',
      );

      // Deleting the transfer puts both balances back.
      await $(find.byTooltip('Delete transfer')).tap();
      await $.dialog.$('Delete').tap();
      await $('Transfer deleted').waitUntilVisible();
      await $.eventually(
        () async =>
            $(ListTile).containing('SBI savings').$(money(10000)).exists,
        reason: 'SBI is back to its opening balance',
      );
    },
  );

  patrolTest('an expense paid from an account lowers its balance, and the '
      'next entry starts on the same account', ($) async {
    await launchSignedIn(
      $,
      seed: (backend, user) async {
        final created = Timestamp.fromDate(DateTime(2026, 1, 1));
        await backend.firestore
            .doc('${FirestorePaths.accounts(user.uid)}/sbi')
            .set({
              'name': 'SBI savings',
              'kind': 'bank',
              'openingBalance': 5000,
              'createdAt': created,
            });
        await backend.firestore
            .doc('${FirestorePaths.accounts(user.uid)}/cash')
            .set({
              'name': 'Cash in hand',
              'kind': 'cash',
              'openingBalance': 1000,
              'createdAt': created,
            });
      },
    );

    await $.addTransaction(
      type: TransactionType.expense,
      amount: 450,
      category: 'Food',
      account: 'Cash in hand',
    );
    await $.dismissSnackBars();

    // The dashboard lists each account with its balance.
    final cash = $(const Key('account-cash'));
    await $.reveal(cash, scrollIn: find.byType(Scrollable).first);
    expect(cash.$(money(550)), findsOneWidget);
    expect($(const Key('account-sbi')).$(money(5000)), findsOneWidget);

    await $.hideKeyboard();
    await $(FloatingActionButton).$('Add').tap();
    await $.sheet.$('Expense').tap();
    await $('Add expense').waitUntilVisible();
    // The amount field takes focus; let the keyboard settle first, or it
    // pushes the row back out of view mid-scroll.
    await $.hideKeyboard();
    final row = $(const Key('account-row'));
    await $.reveal(row, scrollIn: $.transactionFormList);
    expect(row.$('Cash in hand'), findsOneWidget);
  });
}
