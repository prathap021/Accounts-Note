import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:income_expense_tracker/core/constants/app_constants.dart';
import 'package:income_expense_tracker/core/theme/app_theme.dart';
import 'package:patrol/patrol.dart';

import 'support/steps.dart';
import 'support/test_app.dart';

/// A month with some history, logged on another device.
Future<void> _seedHistory(FakeBackend backend, FakeAccount user) async {
  await backend.seedTransaction(
    user.uid,
    id: 'salary',
    type: TransactionType.income,
    amount: 50000,
    category: 'Salary',
    note: 'Monthly salary',
  );
  await backend.seedTransaction(
    user.uid,
    id: 'lunch',
    amount: 450,
    category: 'Food',
    note: 'Team lunch',
  );
  await backend.seedTransaction(
    user.uid,
    id: 'metro',
    amount: 120,
    category: 'Transport',
    note: 'Metro card top-up',
  );
}

void main() {
  patrolTest('history logged on another device is pulled down and listed', (
    $,
  ) async {
    await launchSignedIn($, seed: _seedHistory);

    await $(balance(50000 - 450 - 120)).waitUntilVisible();

    await $.openTab('Activity');
    await $('Monthly salary').waitUntilVisible();
    expect($('Team lunch'), findsOneWidget);
    expect($('Metro card top-up'), findsOneWidget);
    expect($('Synced'), findsOneWidget);
  });

  patrolTest('search narrows the list and shows the total for what matched', (
    $,
  ) async {
    await launchSignedIn($, seed: _seedHistory);
    await $.openTab('Activity');
    await $('Team lunch').waitUntilVisible();

    await $(TextField).first.enterText('lunch');

    await $('TOTAL SPENT').waitUntilVisible();
    expect($('Team lunch'), findsOneWidget);
    expect($('Monthly salary'), findsNothing);
    expect($('Metro card top-up'), findsNothing);

    await $(find.byTooltip('Clear search')).tap();
    await $('Monthly salary').waitUntilVisible();
    expect($('Metro card top-up'), findsOneWidget);
  });

  patrolTest(
    'filtering by type previews the total before applying, then clears',
    ($) async {
      await launchSignedIn($, seed: _seedHistory);
      await $.openTab('Activity');
      await $('Team lunch').waitUntilVisible();

      await $(find.byTooltip('Filter activity')).tap();
      await $('Filter activity').waitUntilVisible();
      expect($('Tap any filter to see its total here.'), findsOneWidget);

      await $.sheet.$(SegmentedButton<TransactionType?>).$('Expense').tap();
      expect(
        $.sheet.$(money(570)),
        findsOneWidget,
        reason: 'the sheet shows what the filter would add up to',
      );

      await $.tapInSheet('Apply');

      await $('TOTAL SPENT').waitUntilVisible();
      expect(
        $(AppCard).containing('TOTAL SPENT').$(money(570)),
        findsOneWidget,
        reason: 'the applied filter shows its own total',
      );
      expect($('Monthly salary'), findsNothing);
      expect($('Team lunch'), findsOneWidget);
      expect(
        $(InputChip).$('Expense'),
        findsOneWidget,
        reason: 'the applied filter is visible and removable',
      );

      await $('Clear all').tap();
      await $('Monthly salary').waitUntilVisible();
      expect($(InputChip), findsNothing);
    },
  );

  patrolTest('filtering by category narrows to that category alone', ($) async {
    await launchSignedIn($, seed: _seedHistory);
    await $.openTab('Activity');
    await $('Team lunch').waitUntilVisible();

    await $(find.byTooltip('Filter activity')).tap();
    await $.tapInSheet($(ChoiceChip).containing('Transport'));
    await $.tapInSheet('Apply');

    await $('Metro card top-up').waitUntilVisible();
    expect($('Team lunch'), findsNothing);
    expect($('Monthly salary'), findsNothing);
  });

  patrolTest(
    'tapping Income on the dashboard opens Activity filtered to income',
    ($) async {
      await launchSignedIn($, seed: _seedHistory);
      await $(balance(50000 - 450 - 120)).waitUntilVisible();

      await $('Income').tap();

      await $('TOTAL RECEIVED').waitUntilVisible();
      expect($('Monthly salary'), findsOneWidget);
      expect($('Team lunch'), findsNothing);

      // The filter belongs to Activity: the dashboard totals ignore it.
      await $.openTab('Home');
      expect($(balance(50000 - 450 - 120)), findsOneWidget);
    },
  );

  patrolTest('swiping a row away asks for confirmation before deleting it', (
    $,
  ) async {
    final (backend, user) = await launchSignedIn($, seed: _seedHistory);
    await $.openTab('Activity');
    await $('Team lunch').waitUntilVisible();

    Future<void> swipeLunch() async {
      await $.tester.drag($('Team lunch'), const Offset(-500, 0));
      await $.pumpAndTrySettle();
    }

    await swipeLunch();
    await $('Delete this transaction?').waitUntilVisible();
    await $.dialog.$('Cancel').tap();
    expect($('Team lunch'), findsOneWidget, reason: 'cancel puts it back');

    await swipeLunch();
    await $.dialog.$('Delete').tap();

    expect($('Team lunch'), findsNothing);
    expect($('Metro card top-up'), findsOneWidget);
    await $.eventually(() async {
      final cloud = await backend.cloudTransactions(user.uid);
      return cloud.length == 2 && cloud.every((t) => t.id != 'lunch');
    }, reason: 'only the swiped entry is deleted from the cloud');
  });

  patrolTest("the dashboard balance carries over last month's leftover", (
    $,
  ) async {
    final now = DateTime.now();
    await launchSignedIn(
      $,
      seed: (backend, user) async {
        await backend.seedTransaction(
          user.uid,
          id: 'last-month-pay',
          type: TransactionType.income,
          amount: 10000,
          category: 'Salary',
          date: DateTime(now.year, now.month - 1, 10),
        );
        await backend.seedTransaction(
          user.uid,
          id: 'last-month-rent',
          amount: 6000,
          category: 'Bills',
          date: DateTime(now.year, now.month - 1, 12),
        );
        await backend.seedTransaction(
          user.uid,
          id: 'today-food',
          amount: 500,
          category: 'Food',
          note: 'Dinner',
        );
      },
    );

    // 10,000 − 6,000 carried in, minus 500 spent this month.
    await $(balance(3500)).waitUntilVisible();
    expect($(RegExp('carried over')), findsOneWidget);

    // Only today's entries are listed on the dashboard.
    await $('Dinner').scrollTo();
    expect($('Bills'), findsNothing);
  });
}
