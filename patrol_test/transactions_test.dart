import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:accounts_note/core/constants/app_constants.dart';
import 'package:patrol/patrol.dart';

import 'support/steps.dart';
import 'support/test_app.dart';

void main() {
  patrolTest(
    'logging income and an expense updates the dashboard and syncs to the cloud',
    ($) async {
      final (backend, user) = await launchSignedIn($);
      await $('No transactions yet').scrollTo();
      expect($('No transactions yet'), findsOneWidget);

      await $.addTransaction(
        type: TransactionType.income,
        amount: 5000,
        category: 'Salary',
        note: 'November pay',
      );
      await $.addTransaction(
        type: TransactionType.expense,
        amount: 250,
        category: 'Food',
        note: 'Groceries',
      );

      await $(balance(4750)).waitUntilVisible();
      expect($(money(5000)), findsWidgets, reason: 'income card');
      expect($(money(250)), findsWidgets, reason: 'expenses card');

      // Both appear under today's activity, newest first.
      await $('Groceries').scrollTo();
      expect($('November pay'), findsOneWidget);
      expect(
        $(signedMoney(250, type: TransactionType.expense)),
        findsOneWidget,
      );
      expect(
        $(signedMoney(5000, type: TransactionType.income)),
        findsOneWidget,
      );

      await $.eventually(
        () async => (await backend.cloudTransactions(user.uid)).length == 2,
        reason: 'both entries reach Firestore',
      );
      final cloud = await backend.cloudTransactions(user.uid);
      expect(
        cloud.map((t) => t.note),
        containsAll(['November pay', 'Groceries']),
      );
    },
  );

  patrolTest('an expense cannot be saved without a valid amount', ($) async {
    final (backend, user) = await launchSignedIn($);

    await $(FloatingActionButton).$('Add').tap();
    await $.sheet.$('Expense').tap();
    await $(FilledButton).$('Add transaction').tap();

    expect($('Enter a valid amount'), findsOneWidget);
    expect($('Add expense'), findsOneWidget, reason: 'still on the form');
    expect(await backend.cloudTransactions(user.uid), isEmpty);
  });

  patrolTest('switching the form to income offers income categories instead', (
    $,
  ) async {
    await launchSignedIn($);

    await $(FloatingActionButton).$('Add').tap();
    await $.sheet.$('Expense').tap();
    expect($(ChoiceChip).$('Food'), findsOneWidget);

    await $(SegmentedButton<TransactionType>).$('Income').tap();

    expect($('Add income'), findsOneWidget);
    expect($(ChoiceChip).$('Salary'), findsOneWidget);
    expect($(ChoiceChip).$('Food'), findsNothing);
  });

  patrolTest('editing a transaction changes it everywhere', ($) async {
    final (backend, user) = await launchSignedIn($);

    await $.addTransaction(
      type: TransactionType.expense,
      amount: 120,
      category: 'Transport',
      note: 'Cab home',
    );
    await $.dismissSnackBars();

    await $('Cab home').scrollTo();
    await $('Cab home').tap();
    await $('Edit transaction').waitUntilVisible();
    expect($('120.00'), findsOneWidget, reason: 'form opens prefilled');

    await $.typeInto($.amountField, '180');
    await $.typeInto(
      $.noteField,
      'Cab home (late night)',
      scrollIn: $.transactionFormList,
    );
    await $('Save changes').tap();

    await waitForScreen($, 'Transaction updated');
    await $('Cab home (late night)').scrollTo();
    expect($(signedMoney(180, type: TransactionType.expense)), findsOneWidget);
    // The balance sits in the header, back at the top.
    await $(balance(-180)).scrollTo(scrollDirection: AxisDirection.up);
    expect($(balance(-180)), findsOneWidget);

    await $.eventually(() async {
      final cloud = await backend.cloudTransactions(user.uid);
      return cloud.length == 1 && cloud.single.amount == 180;
    }, reason: 'the edit is pushed over the original, not added beside it');
  });

  patrolTest(
    'deleting a transaction from its edit screen asks first, then removes it',
    ($) async {
      final (backend, user) = await launchSignedIn($);

      await $.addTransaction(
        type: TransactionType.expense,
        amount: 75,
        category: 'Food',
        note: 'Coffee',
      );
      await $.dismissSnackBars();
      await $.eventually(
        () async => (await backend.cloudTransactions(user.uid)).length == 1,
      );

      await $('Coffee').scrollTo();
      await $('Coffee').tap();
      await $(find.byTooltip('Delete transaction')).tap();

      await $('Delete transaction?').waitUntilVisible();
      await $.dialog.$('Cancel').tap();
      expect($('Edit transaction'), findsOneWidget, reason: 'cancel keeps it');

      await $(find.byTooltip('Delete transaction')).tap();
      await $.dialog.$('Delete').tap();

      // Back on Home, still scrolled down to where the entry was.
      await $('AVAILABLE BALANCE').scrollTo(scrollDirection: AxisDirection.up);
      await $('No transactions yet').scrollTo();
      await $.eventually(
        () async => (await backend.cloudTransactions(user.uid)).isEmpty,
        reason: 'the delete reaches the cloud',
      );
    },
  );

  patrolTest(
    'entries made offline are kept on the device and sync when back online',
    ($) async {
      final (backend, user) = await launchSignedIn($);

      backend.connectivity.online = false;
      await $.addTransaction(
        type: TransactionType.expense,
        amount: 60,
        category: 'Food',
        note: 'Chai on the train',
      );

      // Saved instantly and visible, but marked as still owing a sync.
      await $('Chai on the train').scrollTo();
      expect($('Syncing'), findsOneWidget);
      await $(balance(-60)).scrollTo(scrollDirection: AxisDirection.up);
      expect($(balance(-60)), findsOneWidget);
      expect(await backend.cloudTransactions(user.uid), isEmpty);

      await $.openTab('Activity');
      expect(
        $(RegExp(r'^Pending · 1$')),
        findsOneWidget,
        reason: 'the sync chip counts what is waiting',
      );

      backend.connectivity.online = true;

      await $.eventually(
        () async => (await backend.cloudTransactions(user.uid)).length == 1,
        reason: 'regaining a connection flushes the queue',
      );
      await $('Synced').waitUntilVisible();
      expect($('Syncing'), findsNothing);
    },
  );
}
