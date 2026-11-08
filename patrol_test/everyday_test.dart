import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:income_expense_tracker/core/constants/app_constants.dart';
import 'package:income_expense_tracker/core/utils/money_month.dart';
import 'package:patrol/patrol.dart';

import 'support/steps.dart';
import 'support/test_app.dart';

/// Undo, swipe to edit, months on the dashboard, hiding amounts, the month
/// start day, removing a used category, and starting over.
void main() {
  Future<void> seedLunch(FakeBackend backend, FakeAccount user) =>
      backend.seedTransaction(
        user.uid,
        id: 'lunch',
        amount: 320,
        category: 'Food',
        note: 'Team lunch',
      );

  patrolTest('a deleted entry comes back with Undo', ($) async {
    final (backend, user) = await launchSignedIn($, seed: seedLunch);
    await $.openTab('Activity');
    await $('Team lunch').waitUntilVisible();

    await $.tester.drag($('Team lunch'), const Offset(-500, 0));
    await $.pumpAndTrySettle();
    await $.dialog.$('Delete').tap();
    await $('Deleted Food entry').waitUntilVisible();
    expect($('Team lunch'), findsNothing);

    await $('Undo').tap();
    await $('Team lunch').waitUntilVisible();
    // The delete never reached the cloud.
    final cloud = await backend.cloudTransactions(user.uid);
    expect(cloud.map((t) => t.id), contains('lunch'));
  });

  patrolTest('swiping right opens the entry to edit', ($) async {
    await launchSignedIn($, seed: seedLunch);
    await $.openTab('Activity');
    await $('Team lunch').waitUntilVisible();

    await $.tester.drag($('Team lunch'), const Offset(500, 0));
    await $.pumpAndTrySettle();
    await $('Edit transaction').waitUntilVisible();
  });

  patrolTest('the dashboard steps through months and can hide amounts', (
    $,
  ) async {
    final now = DateTime.now();
    final lastMonth = MoneyMonth.containing(now).previous();
    await launchSignedIn(
      $,
      seed: (backend, user) => backend.seedTransaction(
        user.uid,
        id: 'old-pay',
        type: TransactionType.income,
        amount: 9000,
        category: 'Salary',
        date: lastMonth.start.add(const Duration(days: 2, hours: 10)),
      ),
    );
    final thisMonth = MoneyMonth.containing(now).label;
    expect($(thisMonth), findsWidgets);

    await $(find.byTooltip('Previous month')).tap();
    await $('BALANCE AT MONTH END').waitUntilVisible();
    expect($(lastMonth.label), findsWidgets);
    expect($(money(9000)), findsWidgets, reason: "last month's income");

    await $('Tap to go back to this month').tap();
    await $('AVAILABLE BALANCE').waitUntilVisible();

    await $(find.byTooltip('Hide amounts')).tap();
    await $('••••••').waitUntilVisible();
    expect($(balance(9000)), findsNothing);
    await $(find.byTooltip('Show amounts')).tap();
    await $(balance(9000)).waitUntilVisible();
  });

  patrolTest('a pay-day month start re-cuts the month everywhere', ($) async {
    await launchSignedIn($);
    await $.openSettings();
    await $('Month starts on').tap();
    await $.sheet.$(ChoiceChip).containing('25').tap();
    await $('The 25th, e.g. your pay day').waitUntilVisible();
    await $.leaveSettings();

    final cycle = MoneyMonth.containing(DateTime.now(), 25);
    await $(cycle.label).waitUntilVisible();
  });

  patrolTest('removing a used category moves its entries to Other', ($) async {
    await launchSignedIn(
      $,
      seed: (backend, user) => backend.seedTransaction(
        user.uid,
        id: 'shoes',
        amount: 2400,
        category: 'Shopping',
        note: 'Running shoes',
      ),
    );
    await $.openSettings();
    await $('Manage categories').tap();
    // The categories list, not the Settings list under it.
    await $.reveal($('Shopping'), scrollIn: find.byType(Scrollable).last);
    final row = $(Row).containing('Shopping').containing(IconButton);
    await row.$(find.byTooltip('Remove category')).tap();
    await $(
      '1 transaction uses this category. It will move to "Other" and '
      'stay in your history and totals.',
    ).waitUntilVisible();
    await $.dialog.$('Remove').tap();
    await $('Removed "Shopping". 1 moved to Other.').waitUntilVisible();

    await $.goBack();
    await $.leaveSettings();
    await $.openTab('Activity');
    await $('Running shoes').waitUntilVisible();
    expect($('Other'), findsWidgets);
  });

  patrolTest('clear all data starts over, after typing DELETE', ($) async {
    final (backend, user) = await launchSignedIn($, seed: seedLunch);
    await $.openSettings();
    final clear = $('Clear all data');
    await $.reveal(clear, scrollIn: find.byType(Scrollable).first);
    await clear.tap();
    await $('Clear all data?').waitUntilVisible();

    final confirm = $.dialog.$('Clear everything');
    expect(
      $.tester
          .widget<FilledButton>(
            find.ancestor(of: confirm, matching: find.byType(FilledButton)),
          )
          .onPressed,
      isNull,
      reason: 'disabled until DELETE is typed',
    );
    await $.dialog.$(TextField).enterText('DELETE');
    await $.hideKeyboard();
    await confirm.tap();
    await $(
      'All your data was cleared. The default categories are back.',
    ).waitUntilVisible();

    expect(await backend.cloudTransactions(user.uid), isEmpty);
    await $.leaveSettings();
    await $('No transactions yet').scrollTo();
    // Defaults are back, so a new entry can be added straight away.
    await $.addTransaction(
      type: TransactionType.expense,
      amount: 50,
      category: 'Food',
    );
  });
}
