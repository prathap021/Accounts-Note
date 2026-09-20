import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:income_expense_tracker/core/theme/app_theme.dart';
import 'package:income_expense_tracker/data/repositories/auth_repository.dart';
import 'package:income_expense_tracker/features/auth/forgot_password_sheet.dart';
import 'package:income_expense_tracker/providers/auth_provider.dart';

/// The reset sheet is the only route back in for someone locked out, so its
/// validation and confirmation are worth pinning.
void main() {
  Future<void> pumpSheet(
    WidgetTester tester, {
    String? initialEmail,
    MockFirebaseAuth? auth,
  }) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final repo = AuthRepository(
      auth: auth ?? MockFirebaseAuth(),
      firestore: FakeFirebaseFirestore(),
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [authRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  showForgotPasswordSheet(context, initialEmail: initialEmail),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('explains what the link does', (tester) async {
    await pumpSheet(tester);
    expect(find.text('Reset your password'), findsOneWidget);
    expect(find.textContaining('registered with'), findsOneWidget);
  });

  testWidgets('carries over the email already typed on the sign-in form',
      (tester) async {
    await pumpSheet(tester, initialEmail: 'a.person@example.com');
    expect(find.text('a.person@example.com'), findsOneWidget,
        reason: 'retyping an address you just entered is needless friction');
  });

  group('validation', () {
    testWidgets('rejects an address with no @', (tester) async {
      await pumpSheet(tester);
      await tester.enterText(find.byType(TextFormField), 'not-an-email');
      await tester.tap(find.text('Send reset link'));
      await tester.pumpAndSettle();

      expect(find.text('Enter a valid email'), findsOneWidget);
      expect(find.text('Check your inbox'), findsNothing,
          reason: 'an invalid address must not reach the confirmation screen');
    });

    testWidgets('rejects an empty field', (tester) async {
      await pumpSheet(tester);
      await tester.tap(find.text('Send reset link'));
      await tester.pumpAndSettle();
      expect(find.text('Enter a valid email'), findsOneWidget);
    });
  });

  group('confirmation', () {
    testWidgets('states plainly that the link was sent', (tester) async {
      await pumpSheet(tester);
      await tester.enterText(
        find.byType(TextFormField),
        'a.person@example.com',
      );
      await tester.tap(find.text('Send reset link'));
      await tester.pumpAndSettle();

      expect(find.text('Check your inbox'), findsOneWidget);
      expect(find.textContaining('a.person@example.com'), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);
    });

    testWidgets('offers a way back to correct a typo', (tester) async {
      await pumpSheet(tester);
      await tester.enterText(find.byType(TextFormField), 'typo@example.com');
      await tester.tap(find.text('Send reset link'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Use a different email'));
      await tester.pumpAndSettle();

      expect(find.text('Send reset link'), findsOneWidget,
          reason: 'back to the form, not stuck on the confirmation');
    });
  });

  testWidgets('can be dismissed without sending', (tester) async {
    await pumpSheet(tester);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Reset your password'), findsNothing);
  });
}
