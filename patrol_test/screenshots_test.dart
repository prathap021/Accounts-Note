import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:accounts_note/core/constants/app_constants.dart';
import 'package:accounts_note/models/transaction_model.dart';
import 'package:patrol/patrol.dart';

import 'support/steps.dart';
import 'support/test_app.dart';

/// A tour of the main screens with realistic data, for design review and
/// store screenshots. Not part of the suite: it only runs when built with
/// `--dart-define-from-file=patrol_test/screenshots.json`, and the host
/// grabs the screen each time a `SHOT:<name>` line reaches logcat (see
/// patrol_test/README.md, "Screenshots").
const _enabled = bool.fromEnvironment('SCREENSHOTS');

Future<void> _shot(PatrolIntegrationTester $, String name) async {
  await $.pumpAndTrySettle();
  await Future<void>.delayed(const Duration(milliseconds: 700));
  // ignore: avoid_print
  print('SHOT:$name');
  // Hold still while the host captures the screen.
  await Future<void>.delayed(const Duration(milliseconds: 3200));
}

Future<void> _scroll(PatrolIntegrationTester $, double by) async {
  await $.tester.drag(find.byType(Scrollable).first, Offset(0, -by));
  await $.pumpAndTrySettle();
}

Future<void> _seed(FakeBackend backend, FakeAccount user) async {
  final uid = user.uid;
  final now = DateTime.now();
  DateTime day(int d, int hour) {
    final when = DateTime(now.year, now.month, d.clamp(1, now.day), hour);
    return when.isAfter(now) ? now.subtract(const Duration(hours: 1)) : when;
  }

  final entries = <(String, TransactionType, double, String, String, DateTime)>[
    (
      'salary',
      TransactionType.income,
      65000,
      'Salary',
      'November salary',
      day(1, 10),
    ),
    (
      'logo',
      TransactionType.income,
      12000,
      'Freelance',
      'Logo project',
      day(4, 18),
    ),
    ('rent', TransactionType.expense, 18000, 'Rent', 'Flat rent', day(2, 9)),
    (
      'groceries',
      TransactionType.expense,
      1240,
      'Food',
      'Weekly groceries',
      day(3, 19),
    ),
    (
      'power',
      TransactionType.expense,
      1150,
      'Bills',
      'Electricity',
      day(5, 11),
    ),
    (
      'shoes',
      TransactionType.expense,
      2499,
      'Shopping',
      'Running shoes',
      day(6, 17),
    ),
    (
      'movie',
      TransactionType.expense,
      649,
      'Entertainment',
      'Movie night',
      day(6, 21),
    ),
    (
      'pharmacy',
      TransactionType.expense,
      800,
      'Health',
      'Pharmacy',
      day(7, 12),
    ),
    (
      'metro',
      TransactionType.expense,
      320,
      'Transport',
      'Metro card top-up',
      now.subtract(const Duration(hours: 3)),
    ),
    (
      'lunch',
      TransactionType.expense,
      450,
      'Food',
      'Lunch with the team',
      now.subtract(const Duration(hours: 1)),
    ),
  ];
  for (final (id, type, amount, category, note, date) in entries) {
    await backend.seedTransaction(
      uid,
      id: id,
      type: type,
      amount: amount,
      category: category,
      note: note,
      date: date,
    );
  }

  final created = Timestamp.fromDate(DateTime(now.year, 1, 1));
  await backend.firestore.doc('${FirestorePaths.accounts(uid)}/sbi').set({
    'name': 'SBI savings',
    'kind': 'bank',
    'openingBalance': 40000,
    'createdAt': created,
  });
  await backend.firestore.doc('${FirestorePaths.accounts(uid)}/cash').set({
    'name': 'Cash in hand',
    'kind': 'cash',
    'openingBalance': 2000,
    'createdAt': created,
  });
  await backend.firestore.doc('${FirestorePaths.creditCards(uid)}/hdfc').set({
    'name': 'HDFC Millennia',
    'last4': '4321',
    'color': 0xFF1E3A8A,
    'creditLimit': 100000,
    'createdAt': created,
  });
  final dinnerAt = day(5, 21);
  final dinner = TransactionModel(
    id: 'dinner',
    type: TransactionType.expense,
    amount: 2380,
    categoryId: await backend.categoryId(uid, 'Food'),
    categoryName: 'Food',
    note: 'Birthday dinner',
    date: dinnerAt,
    paymentMethod: kCreditCardPaymentMethod,
    creditCardId: 'hdfc',
    creditCardName: 'HDFC Millennia ••4321',
    createdAt: dinnerAt,
    updatedAt: dinnerAt,
  );
  await backend.firestore
      .doc('${FirestorePaths.transactions(uid)}/dinner')
      .set(dinner.toMap());

  final period = '${now.year}-${now.month.toString().padLeft(2, '0')}';
  final food = await backend.categoryId(uid, 'Food');
  await backend.firestore
      .doc('${FirestorePaths.budgets(uid)}/${period}_$food')
      .set({
        'period': period,
        'categoryId': food,
        'categoryName': 'Food',
        'limit': 6000,
        'alertThresholdPercent': 80,
        'createdAt': Timestamp.now(),
      });
  await backend.firestore
      .doc('${FirestorePaths.budgets(uid)}/${period}_overall')
      .set({
        'period': period,
        'categoryId': null,
        'categoryName': null,
        'limit': 40000,
        'alertThresholdPercent': 80,
        'createdAt': Timestamp.now(),
      });
}

void main() {
  patrolTest('screen tour', skip: !_enabled, ($) async {
    await launchApp($, hasSeenOnboarding: false);
    await $('Next').waitUntilVisible();
    await _shot($, '00_onboarding');

    await launchApp($);
    await $('Continue with Email').waitUntilVisible();
    await _shot($, '01_login');

    await launchSignedIn($, seed: _seed);
    await $.expectDashboard();
    // Let the seeded history sync down and the charts animate in.
    await Future<void>.delayed(const Duration(seconds: 3));
    await _shot($, '02_dashboard');
    await _scroll($, 700);
    await _shot($, '03_dashboard_more');
    await _scroll($, 900);
    await _shot($, '04_dashboard_end');

    await $(FloatingActionButton).$('Add').tap();
    await $.sheet.waitUntilVisible();
    await _shot($, '05_add_sheet');
    await $.sheet.$('Expense').tap();
    await $('Add expense').waitUntilVisible();
    await $.typeInto($.amountField, '450');
    await $.hideKeyboard();
    await _shot($, '06_add_expense');
    await $.goBack();
    await $.pumpAndTrySettle();

    await $.openTab('Activity');
    await _shot($, '07_activity');

    await $.openTab('Budgets');
    await _shot($, '08_budgets');

    await $.openTab('Reports');
    await $('This month so far').waitUntilVisible();
    await _shot($, '09_reports');
    await _scroll($, 900);
    await _shot($, '10_reports_categories');

    await $.openTab('Home');
    await $.openSettings();
    await _shot($, '11_settings');
    await _scroll($, 900);
    await _shot($, '12_settings_more');

    await _scroll($, -3000);
    final accounts = $('Accounts');
    await $.reveal(accounts, scrollIn: find.byType(Scrollable).first);
    await accounts.tap();
    await $('Total in accounts').waitUntilVisible();
    await _shot($, '13_accounts');
    await $.goBack();

    Future<void> visit(String tile, String name) async {
      final row = $(tile);
      await $.reveal(row, scrollIn: find.byType(Scrollable).first);
      await row.tap();
      await $.pumpAndTrySettle();
      await _shot($, name);
      await $.goBack();
      await $.pumpAndTrySettle();
    }

    await visit('Credit cards', '16_credit_cards');
    await visit('Manage categories', '17_categories');
    await _scroll($, -3000);
    await visit('Subscription', '18_subscription');

    final appearance = $('Appearance');
    await $.reveal(appearance, scrollIn: find.byType(Scrollable).first);
    await appearance.tap();
    await $.sheet.$('Dark').tap();
    await $.pumpAndTrySettle();
    await $.leaveSettings();
    await _shot($, '14_dashboard_dark');
    await $.openTab('Activity');
    await _shot($, '15_activity_dark');
  });
}
