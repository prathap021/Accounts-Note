import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';

import 'support/steps.dart';
import 'support/test_app.dart';

/// The PIN and fingerprint lock.
void main() {
  Future<void> typePin(PatrolIntegrationTester $, String pin) async {
    for (final d in pin.split('')) {
      await $(Key('pin-$d')).tap();
    }
    await $.pump(const Duration(milliseconds: 300));
    await $.pumpAndTrySettle();
  }

  Future<void> turnOnLock(PatrolIntegrationTester $, String pin) async {
    await $.openSettings();
    final lock = $(const Key('app-lock'));
    await $.reveal(lock, scrollIn: find.byType(Scrollable).first);
    await lock.tap();
    await $('Choose a 4-digit PIN').waitUntilVisible();
    await typePin($, pin);
    await $('Enter the same PIN again').waitUntilVisible();
    await typePin($, pin);
    await $('App lock is on.').waitUntilVisible();
  }

  patrolTest('with a PIN set, the app opens locked and the PIN unlocks it', (
    $,
  ) async {
    final (backend, _) = await launchSignedIn($);
    await turnOnLock($, '2468');

    await restartApp($, backend);
    await $('Enter your PIN').waitUntilVisible();

    await typePin($, '1111');
    await $(RegExp(r'^Wrong PIN\. 4 tries left')).waitUntilVisible();

    await typePin($, '2468');
    await $.eventually(
      () async => $('Enter your PIN').evaluate().isEmpty,
      reason: 'the lock screen goes away',
    );
    await $.expectDashboard();
  });

  patrolTest('fingerprint unlock opens the app without the PIN', ($) async {
    final (backend, _) = await launchSignedIn($);
    backend.biometrics.available = true;
    await turnOnLock($, '2468');
    final bio = $(const Key('biometric-unlock'));
    await $.reveal(bio, scrollIn: find.byType(Scrollable).first);
    await bio.tap();

    await restartApp($, backend);
    // The fingerprint is asked for straight away and accepted.
    await $.eventually(
      () async => $('Enter your PIN').evaluate().isEmpty,
      reason: 'the fingerprint unlocks the app',
    );
    await $.expectDashboard();
    expect(backend.biometrics.prompts, greaterThanOrEqualTo(2));
  });

  patrolTest('forgot PIN signs out, and signing back in needs no PIN', (
    $,
  ) async {
    final (backend, user) = await launchSignedIn($);
    await turnOnLock($, '2468');

    await restartApp($, backend);
    await $('Forgot PIN?').tap();
    await $('Forgot your PIN?').waitUntilVisible();
    await $.dialog.$('Sign out').tap();
    await $('Continue with Email').waitUntilVisible();

    await $.signInWithEmail(user.email, testPassword);
    await $.expectDashboard();
    expect($('Enter your PIN'), findsNothing);
  });
}
