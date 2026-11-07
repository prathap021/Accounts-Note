import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';

import 'support/test_app.dart';

void main() {
  patrolTest(
    'first launch walks through onboarding to sign-in, and only once',
    ($) async {
      final backend = await launchApp($, hasSeenOnboarding: false);

      await $('Welcome to\nAccounts Note').waitUntilVisible();
      expect($('Log in seconds'), findsOneWidget);

      await $('Next').tap();
      await $('Privacy first').waitUntilVisible();

      await $('Get started').tap();
      await $('Continue with Email').waitUntilVisible();

      // A returning user goes straight to sign-in.
      await restartApp($, backend);
      await $('Continue with Email').waitUntilVisible();
      expect(
        $('Welcome to\nAccounts Note'),
        findsNothing,
        reason: 'onboarding is shown once per install',
      );
    },
  );

  patrolTest('swiping through the intro pages works as well as the buttons', (
    $,
  ) async {
    await launchApp($, hasSeenOnboarding: false);

    await $('Welcome to\nAccounts Note').waitUntilVisible();
    await $.tester.fling(
      $('Welcome to\nAccounts Note'),
      const Offset(-400, 0),
      1000,
    );
    await $.pumpAndTrySettle();

    await $('Privacy first').waitUntilVisible();
    expect(
      $('Get started'),
      findsOneWidget,
      reason: 'the last page offers to finish, not to go further',
    );
  });
}
