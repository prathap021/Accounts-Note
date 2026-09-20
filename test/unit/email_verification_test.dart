import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:income_expense_tracker/data/repositories/auth_repository.dart';

/// Who gets gated behind email verification.
///
/// Getting this wrong either lets unverified addresses in, or — worse — locks
/// out Google and Apple users who have nothing to verify.
UserInfo providerInfo(String id) => UserInfo.fromJson({
      'providerId': id,
      'uid': 'provider-uid',
      'email': 'a.person@example.com',
      'isAnonymous': false,
      'isEmailVerified': true,
    });

MockUser userWith({
  required List<String> providers,
  required bool emailVerified,
}) {
  return MockUser(
    uid: 'uid-1',
    email: 'a.person@example.com',
    isEmailVerified: emailVerified,
    providerData: providers.map(providerInfo).toList(),
  );
}

void main() {
  group('email/password accounts', () {
    test('are gated until the address is confirmed', () {
      final user = userWith(providers: ['password'], emailVerified: false);
      expect(AuthRepository.requiresEmailVerification(user), isTrue);
    });

    test('are let through once confirmed', () {
      final user = userWith(providers: ['password'], emailVerified: true);
      expect(AuthRepository.requiresEmailVerification(user), isFalse);
    });
  });

  group('social accounts are never gated', () {
    test('Google', () {
      final user = userWith(providers: ['google.com'], emailVerified: true);
      expect(AuthRepository.requiresEmailVerification(user), isFalse);
    });

    test('Apple', () {
      final user = userWith(providers: ['apple.com'], emailVerified: true);
      expect(AuthRepository.requiresEmailVerification(user), isFalse);
    });

    test('Google even if Firebase reports the address unverified', () {
      // Some providers report emailVerified false (Apple private relay, for
      // one). Gating them would strand a user who has no link to click.
      final user = userWith(providers: ['google.com'], emailVerified: false);
      expect(AuthRepository.requiresEmailVerification(user), isFalse,
          reason: 'there is no verification email for a social sign-in');
    });
  });

  group('linked accounts', () {
    test('a password provider still gates, even alongside Google', () {
      final user = userWith(
        providers: ['google.com', 'password'],
        emailVerified: false,
      );
      expect(AuthRepository.requiresEmailVerification(user), isTrue,
          reason: 'the password credential needs its own confirmation');
    });

    test('and is released once confirmed', () {
      final user = userWith(
        providers: ['google.com', 'password'],
        emailVerified: true,
      );
      expect(AuthRepository.requiresEmailVerification(user), isFalse);
    });
  });

  group('edge cases', () {
    test('a signed-out user is not gated', () {
      expect(AuthRepository.requiresEmailVerification(null), isFalse);
    });

    test('a user with no provider data is not gated', () {
      final user = userWith(providers: [], emailVerified: false);
      expect(AuthRepository.requiresEmailVerification(user), isFalse,
          reason: 'nothing identifies this as an email sign-up');
    });
  });
}
