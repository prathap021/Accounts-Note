import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:income_expense_tracker/core/theme/app_theme.dart';
import 'package:income_expense_tracker/data/repositories/auth_repository.dart';
import 'package:income_expense_tracker/features/auth/verify_email_screen.dart';
import 'package:income_expense_tracker/providers/auth_provider.dart';

/// The gate an email/password account sits behind until they confirm. It must
/// say which address to look for, offer a resend without letting the user
/// trip Firebase's rate limit, and re-check when they come back from the mail
/// app rather than making them tap.
UserInfo passwordProvider() => UserInfo.fromJson({
      'providerId': 'password',
      'uid': 'provider-uid',
      'email': 'a.person@example.com',
      'isAnonymous': false,
      'isEmailVerified': false,
    });

void main() {
  Future<void> pumpScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final user = MockUser(
      uid: 'uid-1',
      email: 'a.person@example.com',
      isEmailVerified: false,
      providerData: [passwordProvider()],
    );
    final repo = AuthRepository(
      auth: MockFirebaseAuth(signedIn: true, mockUser: user),
      firestore: FakeFirebaseFirestore(),
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [authRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const VerifyEmailScreen(),
      ),
    ));
    await tester.pump();
  }

  testWidgets('names the address the link went to', (tester) async {
    await pumpScreen(tester);
    expect(find.text('Confirm your email'), findsOneWidget);
    expect(find.textContaining('a.person@example.com'), findsOneWidget,
        reason: 'the user needs to know which inbox to open');
  });

  testWidgets('explains that returning to the app re-checks', (tester) async {
    await pumpScreen(tester);
    expect(find.textContaining('return here'), findsOneWidget);
  });

  testWidgets('offers a manual confirm as well', (tester) async {
    await pumpScreen(tester);
    expect(find.text("I've confirmed it"), findsOneWidget);
  });

  testWidgets('holds the resend button behind a cooldown', (tester) async {
    await pumpScreen(tester);

    final resend = find.textContaining('Resend in');
    expect(resend, findsOneWidget,
        reason: 'resending immediately earns a too-many-requests error');

    final button = tester.widget<OutlinedButton>(
      find.ancestor(of: resend, matching: find.byType(OutlinedButton)),
    );
    expect(button.onPressed, isNull, reason: 'disabled during the cooldown');
  });

  testWidgets('offers a way out to a different account', (tester) async {
    await pumpScreen(tester);
    expect(find.text('Use a different account'), findsOneWidget);
  });

  testWidgets('re-checks when the app is resumed, without nagging',
      (tester) async {
    await pumpScreen(tester);

    // Simulate returning from the mail app.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    // Still unverified, but a resume must not throw an error toast — the user
    // may have switched away for an unrelated reason.
    expect(find.textContaining("isn't confirmed yet"), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a manual check does report when still unverified',
      (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.text("I've confirmed it"));
    await tester.pumpAndSettle();

    expect(find.textContaining("isn't confirmed yet"), findsOneWidget,
        reason: 'here the user explicitly claimed to have verified');
  });
}
