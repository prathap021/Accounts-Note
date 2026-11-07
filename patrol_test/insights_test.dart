import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:income_expense_tracker/features/reports/reports_screen.dart';
import 'package:intl/intl.dart';
import 'package:patrol/patrol.dart';

import 'support/steps.dart';
import 'support/test_app.dart';

/// Richer reports, receipt photos and CSV import.
void main() {
  patrolTest('reports break spending down by category, and a category opens '
      'its entries', ($) async {
    await launchSignedIn(
      $,
      seed: (backend, user) async {
        await backend.seedTransaction(
          user.uid,
          id: 'lunch',
          amount: 450,
          category: 'Food',
          note: 'Lunch',
        );
        await backend.seedTransaction(
          user.uid,
          id: 'dinner',
          amount: 300,
          category: 'Food',
          note: 'Dinner',
        );
        await backend.seedTransaction(
          user.uid,
          id: 'power',
          amount: 2000,
          category: 'Bills',
          note: 'Power bill',
        );
      },
    );

    await $.openTab('Reports');
    await $('This month so far').waitUntilVisible();
    final food = $(const Key('report-category-Food'));
    await $.reveal(food, scrollIn: find.byType(Scrollable).first);
    expect(food.$(money(750)), findsOneWidget);
    expect($(const Key('report-category-Bills')).$(money(2000)), findsOne);
    await $('Spending by category').waitUntilExists();

    await food.tap();
    await $('Lunch').waitUntilVisible();
    expect($('Dinner'), findsOneWidget);
    expect($('Power bill'), findsNothing, reason: 'only Food is listed');

    await $.openTab('Reports');
    await $.reveal(
      $(SegmentedButton<ReportRange>),
      scrollIn: find.byType(Scrollable).first,
    );
    await $(SegmentedButton<ReportRange>).$('Day').tap();
    // The tab keeps its scroll position, so the header with its caption may
    // be scrolled away; the period line under the buttons names the day.
    final today = DateFormat('MMM d').format(DateTime.now());
    await $(const Key('report-period')).$('$today – $today').waitUntilVisible();
    expect($(money(2750)), findsWidgets, reason: "today's spending");
  });

  patrolTest('a receipt photo is attached to an expense and opens full size', (
    $,
  ) async {
    await launchSignedIn($);
    await $.hideKeyboard();
    await $(FloatingActionButton).$('Add').tap();
    await $.sheet.$('Expense').tap();
    await $('Add expense').waitUntilVisible();
    await $.typeInto($.amountField, '640');
    final chip = $(ChoiceChip).containing('Food');
    await $.reveal(chip, scrollIn: $.transactionFormList);
    await chip.tap();
    await $.typeInto(
      $.noteField,
      'Team dinner',
      scrollIn: $.transactionFormList,
    );

    final add = $(const Key('receipt-add'));
    await $.reveal(add, scrollIn: $.transactionFormList);
    await add.tap();
    await $.tapInSheet('Choose from gallery');
    await $(const Key('receipt-thumbnail')).waitUntilVisible();
    await $(FilledButton).$('Add transaction').tap();
    await $('Transaction added').waitUntilVisible();
    await $.dismissSnackBars();

    await $.openTab('Activity');
    await $(RegExp('Receipt')).waitUntilVisible();
    await $('Team dinner').tap();
    await $('Edit transaction').waitUntilVisible();
    final thumb = $(const Key('receipt-thumbnail'));
    await $.reveal(thumb, scrollIn: $.transactionFormList);
    await $(Image).waitUntilExists();
    await thumb.tap();
    await $(const Key('receipt-full')).waitUntilVisible();
  });

  patrolTest('entries are imported from a CSV file, once', ($) async {
    final (backend, _) = await launchSignedIn($);
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    backend.csvImport.nextFile =
        'Date,Type,Category,Amount,Note\n'
        '$today 08:00,Expense,Food,180,Imported breakfast\n'
        '$today 09:00,Income,Freelance,2500,Imported gig\n';

    Future<void> importFile() async {
      await $.openSettings();
      final tile = $('Import from CSV');
      await $.reveal(tile, scrollIn: find.byType(Scrollable).first);
      await tile.tap();
      await $('Import 2 entries?').waitUntilVisible();
      expect($('1 income · 1 expense'), findsOneWidget);
      await $.dialog.$('Import').tap();
    }

    await importFile();
    await $('Imported 2 entries.').waitUntilVisible();
    await $.dismissSnackBars();
    await $.leaveSettings();
    await $.openTab('Activity');
    await $('Imported breakfast').waitUntilVisible();
    expect($('Imported gig'), findsOneWidget);

    await $.openTab('Home');
    await importFile();
    await $('Imported 0 entries (2 already here).').waitUntilVisible();
  });
}
