import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:income_expense_tracker/core/constants/app_constants.dart';
import 'package:patrol/patrol.dart';

import 'support/steps.dart';
import 'support/test_app.dart';

ThemeMode _themeMode(PatrolIntegrationTester $) =>
    $.tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode!;

void main() {
  patrolTest('changing the currency reformats every amount', ($) async {
    await launchSignedIn(
      $,
      seed: (backend, user) async {
        await backend.seedTransaction(
          user.uid,
          id: 'pay',
          type: TransactionType.income,
          amount: 1200,
          category: 'Salary',
        );
      },
    );
    await $(balance(1200)).waitUntilVisible();

    await $.openSettings();
    await $('Currency').tap();
    await $.sheet.$('US Dollar').tap();
    expect(
      $('US Dollar · \$'),
      findsOneWidget,
      reason: 'shown as the current choice',
    );

    await $.leaveSettings();
    await $(balance(1200, currency: 'USD')).waitUntilVisible();
    expect($(balance(1200)), findsNothing);
  });

  patrolTest('the chosen appearance applies at once and survives a restart', (
    $,
  ) async {
    final (backend, _) = await launchSignedIn($);
    expect(_themeMode($), ThemeMode.system);

    await $.openSettings();
    await $('Appearance').tap();
    await $.sheet.$('Dark').tap();
    expect(_themeMode($), ThemeMode.dark);

    await restartApp($, backend);
    await $.expectDashboard();
    expect(_themeMode($), ThemeMode.dark);
  });

  patrolTest('editing the display name updates the greeting', ($) async {
    await launchSignedIn($);
    expect($('Asha Rao'), findsOneWidget);

    await $.openSettings();
    await $('Edit name').tap();
    await $.typeInto($.dialog.$(TextField), 'Asha R.');
    await $.dialog.$('Save').tap();
    await $('Asha R.').waitUntilVisible();
    expect(
      $('Profile & settings'),
      findsOneWidget,
      reason: 'saving reloads the user; that must not reset navigation',
    );

    await $.leaveSettings();
    await $('Asha R.').waitUntilVisible();
    expect($('Asha Rao'), findsNothing);
  });

  patrolTest(
    'logging out clears the device, and signing back in restores from the cloud',
    ($) async {
      final (backend, user) = await launchSignedIn($);
      await $.addTransaction(
        type: TransactionType.expense,
        amount: 340,
        category: 'Bills',
        note: 'Electricity',
      );
      await $.eventually(
        () async => (await backend.cloudTransactions(user.uid)).length == 1,
      );

      await $.openSettings();
      await $('Log out').scrollTo();
      await $('Log out').tap();
      await $('Log out?').waitUntilVisible();
      await $.dialog.$('Log out').tap();

      await $('Continue with Email').waitUntilVisible();

      await $.signInWithEmail(user.email, testPassword);
      await $.expectDashboard();
      await $('Electricity').scrollTo();
      expect(
        $(balance(-340)),
        findsOneWidget,
        reason: 'the ledger is rebuilt from the cloud',
      );
    },
  );

  patrolTest('deleting the account removes the cloud data and the sign-in', (
    $,
  ) async {
    final (backend, user) = await launchSignedIn(
      $,
      seed: (backend, user) async {
        await backend.seedTransaction(
          user.uid,
          id: 'to-be-deleted',
          amount: 99,
          category: 'Food',
        );
      },
    );
    await $(balance(-99)).waitUntilVisible();

    await $.openSettings();
    await $('Delete account').scrollTo();
    await $('Delete account').tap();

    await $('Delete your account?').waitUntilVisible();
    expect(
      $(RegExp(r'^Backup & Delete \(\d+\)$')),
      findsOneWidget,
      reason: 'a countdown guards against a reflex tap',
    );

    // The guard holds both buttons for ten seconds.
    await $(
      'Backup & Delete',
    ).waitUntilVisible(timeout: const Duration(seconds: 15));
    await $('Delete without backup').tap();

    await $(
      'Continue with Email',
    ).waitUntilVisible(timeout: const Duration(seconds: 15));
    await $('Your account and data have been deleted').waitUntilVisible();

    expect(backend.auth.accountFor(user.email), isNull);
    final profile = await backend.firestore
        .collection(FirestoreCollections.users)
        .doc(user.uid)
        .get();
    expect(profile.exists, isFalse);
    expect(await backend.cloudTransactions(user.uid), isEmpty);

    // The old credentials no longer work.
    await $.signInWithEmail(user.email, testPassword);
    await $('Incorrect email or password.').waitUntilVisible();
  });

  patrolTest('cancelling the delete dialog leaves the account alone', (
    $,
  ) async {
    final (backend, user) = await launchSignedIn($);

    await $.openSettings();
    await $('Delete account').scrollTo();
    await $('Delete account').tap();
    await $.dialog.$('Cancel').tap();

    expect($('Profile & settings'), findsOneWidget);
    expect(backend.auth.accountFor(user.email), isNotNull);
  });
}
