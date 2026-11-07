import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:income_expense_tracker/features/lock/lock_screen.dart';
import 'package:income_expense_tracker/providers/app_lock_provider.dart';
import 'package:income_expense_tracker/providers/auth_provider.dart';
import 'package:income_expense_tracker/providers/settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_notifications.dart';

void main() {
  late SharedPreferences prefs;
  late FakeBiometrics bio;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    bio = FakeBiometrics();
  });

  ProviderContainer launch() {
    final c = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        biometricUnlockProvider.overrideWithValue(bio),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  test('a PIN is stored only as a hash, and every launch locks', () async {
    final c = launch();
    expect(c.read(appLockProvider).enabled, isFalse);
    await c.read(appLockProvider.notifier).setPin('2468');
    expect(c.read(appLockProvider).locked, isFalse);
    for (final key in prefs.getKeys()) {
      expect('${prefs.get(key)}', isNot(contains('2468')));
    }

    final again = launch();
    expect(again.read(appLockProvider).locked, isTrue, reason: 'cold start');
    expect(again.read(appLockProvider.notifier).unlock('1111'), isFalse);
    expect(again.read(appLockProvider.notifier).unlock('2468'), isTrue);
    expect(again.read(appLockProvider).locked, isFalse);
  });

  test('five wrong PINs pause the keypad for 30 seconds', () async {
    final c = launch();
    final n = c.read(appLockProvider.notifier);
    await n.setPin('2468');
    final t0 = DateTime(2026, 11, 7, 10);
    for (var i = 0; i < 5; i++) {
      expect(n.unlock('0000', now: t0), isFalse);
    }
    expect(c.read(appLockProvider).lockedOutUntil, isNotNull);
    expect(
      n.unlock('2468', now: t0.add(const Duration(seconds: 10))),
      isFalse,
      reason: 'even the right PIN waits',
    );
    expect(n.unlock('2468', now: t0.add(const Duration(seconds: 31))), isTrue);
  });

  test(
    'locks again after 30 s in the background, not after a glance away',
    () async {
      final c = launch();
      final n = c.read(appLockProvider.notifier);
      await n.setPin('2468');

      n.appBackgrounded();
      n.appResumed(now: DateTime.now().add(const Duration(seconds: 5)));
      expect(c.read(appLockProvider).locked, isFalse);

      n.appBackgrounded();
      n.appResumed(now: DateTime.now().add(const Duration(seconds: 45)));
      expect(c.read(appLockProvider).locked, isTrue);
    },
  );

  test('fingerprint unlock needs a working fingerprint to turn on', () async {
    final c = launch();
    final n = c.read(appLockProvider.notifier);
    await n.setPin('2468');
    expect(await n.setBiometrics(true), isFalse, reason: 'none on the phone');

    bio.available = true;
    expect(await n.setBiometrics(true), isTrue);
    final again = launch();
    expect(again.read(appLockProvider).locked, isTrue);
    expect(
      await again.read(appLockProvider.notifier).unlockWithBiometrics(),
      isTrue,
    );
    expect(again.read(appLockProvider).locked, isFalse);
  });

  test('turning the lock off forgets the PIN', () async {
    final c = launch();
    final n = c.read(appLockProvider.notifier);
    await n.setPin('2468');
    await n.disable();
    expect(launch().read(appLockProvider).locked, isFalse);
    expect(n.checkPin('2468'), isFalse);
  });

  testWidgets('the lock screen covers the app until the PIN is typed', (
    tester,
  ) async {
    final c = launch();
    await c.read(appLockProvider.notifier).setPin('1357');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          biometricUnlockProvider.overrideWithValue(bio),
          currentUidProvider.overrideWithValue('u'),
        ],
        child: const MaterialApp(
          home: AppLockGate(child: Scaffold(body: Text('THE APP'))),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Enter your PIN'), findsOneWidget);

    for (final d in '0000'.split('')) {
      await tester.tap(find.byKey(Key('pin-$d')));
    }
    await tester.pumpAndSettle();
    expect(find.textContaining('Wrong PIN. 4 tries left'), findsOneWidget);

    for (final d in '1357'.split('')) {
      await tester.tap(find.byKey(Key('pin-$d')));
    }
    await tester.pumpAndSettle();
    expect(find.text('Enter your PIN'), findsNothing);
    expect(find.text('THE APP'), findsOneWidget);
  });

  testWidgets('Forgot PIN asks before signing out, even above the router', (
    tester,
  ) async {
    final c = launch();
    await c.read(appLockProvider.notifier).setPin('1357');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          biometricUnlockProvider.overrideWithValue(bio),
          currentUidProvider.overrideWithValue('u'),
        ],
        child: MaterialApp(
          // As in the app: the gate wraps the navigator from the builder.
          builder: (_, child) => AppLockGate(child: child!),
          home: const Scaffold(body: Text('THE APP')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Forgot PIN?'));
    await tester.pumpAndSettle();
    expect(find.text('Forgot your PIN?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Enter your PIN'), findsOneWidget);
  });
}
