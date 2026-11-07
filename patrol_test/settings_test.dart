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
    final appearance = $('Appearance');
    await $.reveal(appearance, scrollIn: find.byType(Scrollable).first);
    await appearance.tap();
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

  patrolTest('every Play currency can be found and used, with its own format', (
    $,
  ) async {
    await launchSignedIn(
      $,
      seed: (backend, user) async {
        await backend.seedTransaction(
          user.uid,
          id: 'pay',
          type: TransactionType.income,
          amount: 1500,
          category: 'Salary',
        );
      },
    );
    await $(balance(1500)).waitUntilVisible();

    await $.openSettings();
    await $('Currency').tap();
    await $('Suggested').waitUntilVisible();
    expect($('All currencies'), findsOneWidget);

    await $.sheet.$(TextField).enterText('yen');
    await $.hideKeyboard();
    await $.sheet.$('Japanese Yen').tap();
    await $('Japanese Yen · ¥').waitUntilVisible();

    await $.leaveSettings();
    // The yen has no minor units, so no ".00".
    await $(balance(1500, currency: 'JPY')).waitUntilVisible();
    expect(balance(1500, currency: 'JPY'), '¥ 1,500');
  });

  patrolTest('About offers rating the app and checking for updates', ($) async {
    await launchSignedIn($);
    await $.openSettings();

    final rate = $('Rate Accounts Note');
    await $.reveal(rate, scrollIn: find.byType(Scrollable).first);
    expect($('Leave a review on Google Play'), findsOneWidget);

    final check = $('Check for updates');
    await $.reveal(check, scrollIn: find.byType(Scrollable).first);
    await check.tap();
    // This build was installed by the test runner, not from Google Play.
    await $(
      'Updates are only available for the Google Play version of the app.',
    ).waitUntilVisible();
  });

  patrolTest('a backup moves every transaction into another account', (
    $,
  ) async {
    final (backend, asha) = await launchSignedIn(
      $,
      seed: (backend, user) async {
        await backend.seedTransaction(
          user.uid,
          id: 'b-pay',
          type: TransactionType.income,
          amount: 25000,
          category: 'Salary',
          note: 'October salary',
        );
        await backend.seedTransaction(
          user.uid,
          id: 'b-food',
          amount: 640,
          category: 'Food',
          note: 'Groceries',
        );
        await backend.seedUser(
          email: 'ravi@example.com',
          displayName: 'Ravi Kumar',
          signedIn: false,
        );
        // Setting Ravi up signed him in and out; Asha is the one using the
        // phone.
        await backend.auth.signInWithEmailAndPassword(
          email: user.email,
          password: testPassword,
        );
      },
    );

    // Asha backs up. The file is made from her cloud copy.
    await $.openSettings();
    final backup = $('Back up now');
    await $.reveal(backup, scrollIn: find.byType(Scrollable).first);
    await backup.tap();
    await $('Backup ready with 2 transactions.').waitUntilVisible();
    expect(
      backend.backupFiles.lastSharedName,
      matches(RegExp(r'^accounts_note_backup_\d{4}-\d{2}-\d{2}\.json$')),
    );

    // Ravi signs in on the same phone and imports it.
    await $.dismissSnackBars();
    await $('Log out').scrollTo();
    await $('Log out').tap();
    await $.dialog.$('Log out').tap();
    await $('Continue with Email').waitUntilVisible();
    await $.signInWithEmail('ravi@example.com', testPassword);
    await $.expectDashboard();
    expect($('October salary'), findsNothing);

    await $.openSettings();
    final import = $('Import a backup');
    await $.reveal(import, scrollIn: find.byType(Scrollable).first);
    await import.tap();
    await $('Import this backup?').waitUntilVisible();
    expect($('2 transactions'), findsOneWidget);
    await $.dialog.$('Import').tap();
    await $('Imported 2 transactions.').waitUntilVisible();

    await $.leaveSettings();
    await $.openTab('Activity');
    await $('October salary').waitUntilVisible();
    expect($('Groceries'), findsOneWidget);

    // Asha's own account still has them too.
    final ashaTx = await backend.cloudTransactions(asha.uid);
    expect(ashaTx, hasLength(2));
  });
}
