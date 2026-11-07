import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:income_expense_tracker/core/constants/app_constants.dart';
import 'package:patrol/patrol.dart';

import 'support/steps.dart';
import 'support/test_app.dart';

void main() {
  group('Sign up', () {
    patrolTest(
      'a new email account must confirm its address before reaching the app',
      ($) async {
        final backend = await launchApp($);
        const email = 'new.person@example.com';

        await $.signUpWithEmail(email, testPassword);

        await $('Confirm your email').waitUntilVisible();
        expect(
          $(RegExp(RegExp.escape(email))),
          findsOneWidget,
          reason: 'the screen says where the link went',
        );
        expect(
          $(RegExp(r'^Resend in \d+s$')),
          findsOneWidget,
          reason: 'resending is held back to respect rate limits',
        );
        expect(
          backend.auth.accountFor(email)!.verificationEmailsSent,
          1,
          reason: 'exactly one link is sent on sign-up, not a duplicate',
        );

        // Claiming to have confirmed before opening the link changes nothing.
        await $("I've confirmed it").tap();
        await $(RegExp("isn't confirmed yet")).waitUntilVisible();
        expect($('Confirm your email'), findsOneWidget);

        backend.auth.confirmEmailFromInbox(email);
        await $("I've confirmed it").tap();
        await $.expectDashboard();

        // First sign-in created the profile and the starter categories.
        final uid = backend.auth.accountFor(email)!.uid;
        final categories = await backend.firestore
            .collection(FirestorePaths.categories(uid))
            .get();
        expect(
          categories.docs.length,
          kDefaultExpenseCategories.length + kDefaultIncomeCategories.length,
        );
      },
    );

    patrolTest(
      'returning from the inbox app re-checks verification without a tap',
      ($) async {
        final backend = await launchApp($);
        const email = 'inbox.return@example.com';

        await $.signUpWithEmail(email, testPassword);
        await $('Confirm your email').waitUntilVisible();

        // The user leaves for their mail app and opens the link there.
        await $.platform.mobile.pressHome();
        backend.auth.confirmEmailFromInbox(email);
        await $.platform.mobile.openApp();

        await $.expectDashboard();
      },
    );

    patrolTest('an address that already has an account is refused', ($) async {
      final backend = FakeBackend();
      await backend.seedUser(signedIn: false);
      await launchApp($, backend: backend);

      await $.signUpWithEmail('asha@example.com', 'another-password');

      await $('An account already exists with this email.').waitUntilVisible();
      expect(
        $('Create your account'),
        findsOneWidget,
        reason: 'the user stays on the form to fix it',
      );
    });

    patrolTest(
      'choosing a different account from the verification screen signs out',
      ($) async {
        await launchApp($);

        await $.signUpWithEmail('typo@exmaple.com', testPassword);
        await $('Confirm your email').waitUntilVisible();

        await $('Use a different account').tap();
        await $('Continue with Email').waitUntilVisible();
      },
    );
  });

  group('Sign in', () {
    patrolTest('the form explains what is wrong before contacting the server', (
      $,
    ) async {
      await launchApp($);

      await $.openEmailForm();
      await $(FilledButton).$('Sign in').tap();

      expect($('Enter a valid email'), findsOneWidget);
      expect($('Password must be at least 6 characters'), findsOneWidget);
    });

    patrolTest('a wrong password is rejected, then the right one signs in', (
      $,
    ) async {
      final backend = FakeBackend();
      await backend.seedUser(signedIn: false);
      await launchApp($, backend: backend);

      await $.signInWithEmail('asha@example.com', 'wrong-password');
      await $('Incorrect email or password.').waitUntilVisible();
      expect($('Sign in with email'), findsOneWidget);

      await $.typeInto($(TextFormField).at(1), testPassword);
      await $(FilledButton).$('Sign in').tap();

      await $.expectDashboard();
      expect($('Asha Rao'), findsOneWidget, reason: 'greeted by name');
    });

    patrolTest('a signed-in session survives the app being closed', ($) async {
      final backend = FakeBackend();
      await backend.seedUser(signedIn: false);
      await launchApp($, backend: backend);
      await $.signInWithEmail('asha@example.com', testPassword);
      await $.expectDashboard();

      await restartApp($, backend);

      await $.expectDashboard();
      expect($('Continue with Email'), findsNothing);
    });
  });

  group('Password reset', () {
    patrolTest(
      'the address typed on the sign-in form is carried into the reset sheet',
      ($) async {
        final backend = FakeBackend();
        await backend.seedUser(signedIn: false);
        await launchApp($, backend: backend);

        await $.openEmailForm();
        await $.typeInto($(TextFormField).at(0), 'asha@example.com');
        await $('Forgot password?').tap();

        await $('Reset your password').waitUntilVisible();
        await $('Send reset link').tap();

        await $('Check your inbox').waitUntilVisible();
        expect(
          $(RegExp('We sent a reset link to asha@example.com')),
          findsOneWidget,
        );
        expect(backend.auth.passwordResetsSentTo, ['asha@example.com']);

        await $('Done').tap();
        expect($('Reset your password'), findsNothing);
        expect($('Sign in with email'), findsOneWidget);
      },
    );

    patrolTest('an invalid address is caught in the sheet', ($) async {
      final backend = await launchApp($);

      await $.openEmailForm();
      await $('Forgot password?').tap();
      await $('Reset your password').waitUntilVisible();

      await $.typeInto($.sheet.$(TextFormField), 'not-an-email');
      await $('Send reset link').tap();

      expect($.sheet.$('Enter a valid email'), findsOneWidget);
      expect(backend.auth.passwordResetsSentTo, isEmpty);
    });
  });
}
