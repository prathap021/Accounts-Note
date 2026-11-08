import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:accounts_note/core/constants/app_constants.dart';
import 'package:accounts_note/features/reports/reports_screen.dart';
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

  patrolTest(
    'Reports cover a past period picked on the calendar, and export it',
    ($) async {
      final lastYear = DateTime.now().year - 1;
      await launchSignedIn(
        $,
        seed: (backend, user) async {
          await backend.seedTransaction(
            user.uid,
            id: 'old-bonus',
            type: TransactionType.income,
            amount: 15000,
            category: 'Salary',
            date: DateTime(lastYear, 3, 10, 10),
          );
          await backend.seedTransaction(
            user.uid,
            id: 'old-rent',
            amount: 6000,
            category: 'Bills',
            date: DateTime(lastYear, 3, 31, 21),
          );
          await backend.seedTransaction(
            user.uid,
            id: 'now',
            type: TransactionType.income,
            amount: 1234,
            category: 'Salary',
          );
        },
      );
      await $.openTab('Reports');
      await $('This month so far').waitUntilVisible();

      // Cancelling the calendar leaves the report alone.
      await $(SegmentedButton<ReportRange>).$('Custom').tap();
      await $('Select report period').waitUntilVisible();
      await $(find.byTooltip('Close')).tap();
      await $('This month so far').waitUntilVisible();
      expect($(money(1234)), findsWidgets);

      // Last March, typed in the calendar's text mode.
      String typed(int m, int d) =>
          '${m.toString().padLeft(2, '0')}/${d.toString().padLeft(2, '0')}/$lastYear';
      await $(SegmentedButton<ReportRange>).$('Custom').tap();
      await $(find.byTooltip('Switch to input')).tap();
      await $(TextField).at(0).enterText(typed(3, 1));
      await $(TextField).at(1).enterText(typed(3, 31));
      await $.hideKeyboard();
      await $('Generate').tap();

      await $('Custom range').waitUntilVisible();
      expect($('1 Mar $lastYear – 31 Mar $lastYear'), findsOneWidget);
      expect($(money(15000)), findsWidgets);
      expect(
        $(money(6000)),
        findsWidgets,
        reason: '9 pm on the last day still counts',
      );
      expect($(money(1234)), findsNothing, reason: 'this month is outside');

      // Export asks for the file type.
      await $(find.byTooltip('Export report')).tap();
      await $('Export report').waitUntilVisible();
      expect($('2 transactions'), findsNothing);
      expect($(RegExp(r'· 2 transactions$')), findsOneWidget);
      expect($('PDF document'), findsOneWidget);
      expect($('Excel spreadsheet'), findsOneWidget);
      expect($('CSV file'), findsOneWidget);
    },
  );
}
