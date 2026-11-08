import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:accounts_note/core/constants/app_constants.dart';
import 'package:accounts_note/core/services/notifications.dart';
import 'package:accounts_note/core/utils/money_month.dart';
import 'package:accounts_note/models/recurring_rule.dart';
import 'package:patrol/patrol.dart';

import 'support/steps.dart';
import 'support/test_app.dart';

/// Recurring transactions, the daily reminder and budget alerts.
void main() {
  patrolTest('a repeating expense is added when it comes due, and can pause', (
    $,
  ) async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month - 2, 1, 9);
    await launchSignedIn(
      $,
      seed: (backend, user) async {
        final rent = await backend.categoryId(user.uid, 'Rent');
        final rule = RecurringRule(
          id: 'rent',
          type: TransactionType.expense,
          amount: 15000,
          categoryId: rent,
          categoryName: 'Rent',
          note: 'Flat rent',
          paymentMethod: 'UPI',
          frequency: RecurrenceFrequency.monthly,
          startDate: start,
          lastGenerated: start,
          createdAt: start,
        );
        await backend.firestore
            .doc('${FirestorePaths.recurring(user.uid)}/rent')
            .set(rule.toMap());
      },
    );

    // Two months were missed while the app was closed.
    await $('Added 2 recurring entries that came due.').waitUntilVisible();
    await $.dismissSnackBars();
    await $.openTab('Activity');
    await $('Flat rent').waitUntilVisible();
    expect($('Flat rent'), findsNWidgets(2));

    await $.openTab('Home');
    await $.openSettings();
    final tile = $('Recurring transactions');
    await $.reveal(tile, scrollIn: find.byType(Scrollable).first);
    await tile.tap();
    await $(RegExp(r'^Next: ')).waitUntilVisible();
    await $('Pause').tap();
    await $('Paused').waitUntilVisible();
    await $('Resume').waitUntilVisible();
  });

  patrolTest('turning on Repeat in the form sets up the rule', ($) async {
    await launchSignedIn($);
    await $.hideKeyboard();
    await $(FloatingActionButton).$('Add').tap();
    await $.sheet.$('Expense').tap();
    await $('Add expense').waitUntilVisible();
    await $.typeInto($.amountField, '899');
    final chip = $(ChoiceChip).containing('Bills');
    await $.reveal(chip, scrollIn: $.transactionFormList);
    await chip.tap();
    await $.typeInto(
      $.noteField,
      'Phone plan',
      scrollIn: $.transactionFormList,
    );

    final repeat = $(const Key('repeat-switch'));
    await $.reveal(repeat, scrollIn: $.transactionFormList);
    await repeat.tap();
    await $(ChoiceChip).containing('Monthly').waitUntilVisible();
    await $(FilledButton).$('Add transaction').tap();
    await $('Transaction added. It repeats monthly.').waitUntilVisible();

    await $.openSettings();
    final tile = $('Recurring transactions');
    await $.reveal(tile, scrollIn: find.byType(Scrollable).first);
    await tile.tap();
    await $('Phone plan').waitUntilVisible();
    expect($(RegExp(r'^Monthly · Bills')), findsOneWidget);
  });

  patrolTest('the daily reminder is set, and tapping it opens a new expense', (
    $,
  ) async {
    final (backend, _) = await launchSignedIn($);
    await $.openSettings();
    final reminder = $(const Key('daily-reminder'));
    await $.reveal(reminder, scrollIn: find.byType(Scrollable).first);
    await reminder.tap();
    await $(RegExp(r'^Every day at ')).waitUntilVisible();
    expect(backend.notifications.dailyAt, const TimeOfDay(hour: 21, minute: 0));

    await $.leaveSettings();
    backend.notifications.tap(NotificationAction.addExpense);
    await $('Add expense').waitUntilVisible();
  });

  patrolTest('spending past 80% of a budget raises an alert', ($) async {
    final (backend, _) = await launchSignedIn(
      $,
      seed: (backend, user) async {
        final food = await backend.categoryId(user.uid, 'Food');
        final period = MoneyMonth.containing(DateTime.now()).key;
        await backend.firestore
            .doc('${FirestorePaths.budgets(user.uid)}/${period}_$food')
            .set({
              'period': period,
              'categoryId': food,
              'categoryName': 'Food',
              'limit': 1000,
              'alertThresholdPercent': 80,
              'createdAt': Timestamp.now(),
            });
      },
    );

    await $.addTransaction(
      type: TransactionType.expense,
      amount: 850,
      category: 'Food',
    );
    await $.eventually(
      () async => backend.notifications.shown.isNotEmpty,
      reason: 'the alert is raised once the expense is saved',
    );
    expect(backend.notifications.shown.single.title, 'Food budget 80% used');

    // Tapping it opens Budgets.
    backend.notifications.tap(NotificationAction.openBudgets);
    await $('Food').waitUntilVisible();
  });
}
