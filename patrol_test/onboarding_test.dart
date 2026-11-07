import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';

import 'support/steps.dart';
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

      // First run: the currency, from the phone's location if allowed.
      await $('Set your currency').waitUntilVisible();
      expect($(RegExp("isn't saved or sent anywhere")), findsOneWidget);
      await $('Use my location').tap();
      if (await $.platform.mobile.isPermissionDialogVisible(
        timeout: const Duration(seconds: 5),
      )) {
        await $.platform.mobile.grantPermissionWhenInUse();
      }
      // The emulator places itself in the US. Without a geocoder it cannot
      // name the country, and the region's currency is kept instead.
      await $.eventually(
        () async =>
            $(RegExp(r'^Currency set to ')).exists ||
            $(RegExp("Couldn't find your location")).exists,
        timeout: const Duration(seconds: 20),
        reason: 'the location lookup finishes either way',
      );
      if ($('Continue').exists) await $('Continue').tap();
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
