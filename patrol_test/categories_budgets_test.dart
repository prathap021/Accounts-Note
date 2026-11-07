import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:income_expense_tracker/core/constants/app_constants.dart';
import 'package:patrol/patrol.dart';

import 'support/steps.dart';
import 'support/test_app.dart';

void main() {
  group('Categories', () {
    patrolTest('a new category can be created and used for an expense', (
      $,
    ) async {
      await launchSignedIn($);
      await $.openSettings();
      await $('Manage categories').tap();
      await $('Categories').waitUntilVisible();

      await $(FloatingActionButton).$('New category').tap();
      await $.tapInSheet('Create category');
      expect(
        $('Give this category a name'),
        findsOneWidget,
        reason: 'a nameless category is refused',
      );

      await $.typeInto($.sheet.$(TextField), 'Pets');
      await $.tapInSheet('Create category');

      await $('Pets').scrollTo();
      expect($('Pets'), findsOneWidget);

      // Back to the dashboard and spend in it.
      await $.goBack();
      await $.leaveSettings();
      await $.addTransaction(
        type: TransactionType.expense,
        amount: 900,
        category: 'Pets',
        note: 'Vet visit',
      );
      await $('Vet visit').scrollTo();
      expect($('Pets'), findsWidgets);
    });

    patrolTest('income and expense categories are kept apart', ($) async {
      await launchSignedIn($);
      await $.openSettings();
      await $('Manage categories').tap();

      await $('Food').waitUntilVisible();
      expect($('Salary'), findsNothing);

      await $(Tab).$('Income').tap();
      await $('Salary').waitUntilVisible();
      expect($('Food'), findsNothing);
    });

    patrolTest('removing a category asks first and takes it off the list', (
      $,
    ) async {
      await launchSignedIn($);
      await $.openSettings();
      await $('Manage categories').tap();
      await $('Education').scrollTo();

      final row = $(Row).containing('Education').containing(IconButton);
      await row.$(find.byTooltip('Remove category')).tap();
      await $('Remove "Education"?').waitUntilVisible();
      await $.dialog.$('Remove').tap();

      await $.pumpAndTrySettle();
      expect($('Education'), findsNothing);
    });
  });

  group('Budgets', () {
    patrolTest('a category budget tracks spending against its limit', (
      $,
    ) async {
      await launchSignedIn($);
      await $.openTab('Budgets');
      await $('No budgets this month').waitUntilVisible();

      await $(FloatingActionButton).$('New budget').tap();
      await $.tapInSheet('Save budget');
      expect($('Enter a limit greater than zero'), findsOneWidget);

      await $.hideKeyboard();
      await $.sheet.$(DropdownButtonFormField<String?>).tap();
      await $(DropdownMenuItem<String?>).$('Food').last.tap();
      await $.typeInto($.sheet.$(TextField), '1000');
      await $.tapInSheet('Save budget');

      await $('${money(0)} of ${money(1000)}').waitUntilVisible();

      await $.openTab('Home');
      await $.addTransaction(
        type: TransactionType.expense,
        amount: 250,
        category: 'Food',
      );

      await $.openTab('Budgets');
      await $('${money(250)} of ${money(1000)}').waitUntilVisible();
      expect($('25%'), findsOneWidget);
      expect($('${money(750)} left'), findsOneWidget);
    });

    patrolTest('an overspent overall budget says by how much', ($) async {
      await launchSignedIn(
        $,
        seed: (backend, user) async {
          await backend.seedTransaction(
            user.uid,
            id: 'big-shop',
            amount: 1500,
            category: 'Shopping',
          );
        },
      );
      await $.openTab('Budgets');

      await $(FloatingActionButton).$('New budget').tap();
      await $.typeInto($.sheet.$(TextField), '1000');
      await $.tapInSheet('Save budget');

      await $('Overall budget').waitUntilVisible();
      await $('${money(500)} over').waitUntilVisible();
    });

    patrolTest('deleting a budget asks first', ($) async {
      await launchSignedIn($);
      await $.openTab('Budgets');
      await $(FloatingActionButton).$('New budget').tap();
      await $.typeInto($.sheet.$(TextField), '2000');
      await $.tapInSheet('Save budget');
      await $('Overall budget').waitUntilVisible();

      await $(find.byTooltip('Delete budget')).tap();
      await $('Delete this budget?').waitUntilVisible();
      await $.dialog.$('Delete').tap();

      await $('No budgets this month').waitUntilVisible();
    });
  });
}
