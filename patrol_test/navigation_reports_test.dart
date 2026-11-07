import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:income_expense_tracker/core/constants/app_constants.dart';
import 'package:income_expense_tracker/features/reports/reports_screen.dart';
import 'package:patrol/patrol.dart';

import 'support/steps.dart';
import 'support/test_app.dart';

void main() {
  patrolTest('every tab in the bottom bar opens its screen', ($) async {
    await launchSignedIn($);

    await $.openTab('Activity');
    await $('Your ledger').waitUntilVisible();

    await $.openTab('Budgets');
    await $('No budgets this month').waitUntilVisible();

    await $.openTab('Reports');
    await $('Nothing to report yet').waitUntilVisible();

    await $.openTab('Home');
    await $.expectDashboard();
  });

  patrolTest(
    'Android back returns to Home first, then asks before leaving',
    skip: !Platform.isAndroid,
    ($) async {
      await launchSignedIn($);

      await $.openTab('Reports');
      await $('Nothing to report yet').waitUntilVisible();

      await $.platform.android.pressBack();
      await $.expectDashboard();
      expect(
        $('Press back again to exit'),
        findsNothing,
        reason: 'a back that only went home is not half an exit',
      );

      await $.platform.android.pressBack();
      await $('Press back again to exit').waitUntilVisible();
      await $.expectDashboard();
    },
  );

  patrolTest(
    'Android back closes a pushed screen instead of the app',
    skip: !Platform.isAndroid,
    ($) async {
      await launchSignedIn($);

      await $.openSettings();
      await $.platform.android.pressBack();

      await $.expectDashboard();
      expect($('Press back again to exit'), findsNothing);
    },
  );

  patrolTest('Reports totals the period and switches ranges', ($) async {
    await launchSignedIn(
      $,
      seed: (backend, user) async {
        await backend.seedTransaction(
          user.uid,
          id: 'r-pay',
          type: TransactionType.income,
          amount: 20000,
          category: 'Salary',
        );
        await backend.seedTransaction(
          user.uid,
          id: 'r-rent',
          amount: 8000,
          category: 'Bills',
        );
      },
    );

    await $.openTab('Reports');
    await $('This month so far').waitUntilVisible();
    await $(money(20000)).waitUntilVisible();
    expect($(money(8000)), findsWidgets);
    expect($('Income vs expenses'), findsOneWidget);

    await $(SegmentedButton<ReportRange>).$('Year').tap();
    await $('This year so far').waitUntilVisible();
    expect(
      $(money(20000)),
      findsWidgets,
      reason: 'this month is inside this year',
    );
  });
}
