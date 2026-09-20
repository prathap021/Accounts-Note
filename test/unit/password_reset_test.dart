import 'package:flutter_test/flutter_test.dart';
import 'package:income_expense_tracker/data/repositories/auth_repository.dart';

/// Wording shown when a password-reset request fails.
///
/// The unregistered-address case is the one the reset screen exists to
/// communicate, so it is pinned explicitly.
void main() {
  String messageFor(String code) =>
      AuthRepository.passwordResetErrorMessage(code);

  test('an unregistered address asks for a registered one', () {
    expect(
      messageFor('user-not-found'),
      'Please enter a registered email address.',
    );
  });

  test('a malformed address is called out separately', () {
    expect(
      messageFor('invalid-email'),
      'Please enter a valid email address.',
    );
    expect(
      messageFor('invalid-email'),
      isNot(messageFor('user-not-found')),
      reason: 'a typo and an unknown account need different advice',
    );
  });

  test('an empty address asks for one', () {
    expect(messageFor('missing-email'), contains('enter your email'));
  });

  test('rate limiting explains the wait', () {
    expect(messageFor('too-many-requests'), contains('wait a minute'));
  });

  test('a network failure blames the connection, not the address', () {
    final message = messageFor('network-request-failed');
    expect(message, contains('connection'));
    expect(message, isNot(contains('registered')),
        reason: 'a dropped connection says nothing about the account');
  });

  test('an unknown code still produces usable copy', () {
    final message = messageFor('something-unexpected');
    expect(message, isNotEmpty);
    expect(message, contains('try again'));
  });

  test('no message leaks internal codes to the user', () {
    for (final code in [
      'user-not-found',
      'invalid-email',
      'missing-email',
      'too-many-requests',
      'network-request-failed',
      'internal-error',
    ]) {
      expect(messageFor(code), isNot(contains(code)));
      expect(messageFor(code), isNot(contains('-')),
          reason: 'raw Firebase codes must not surface in the UI');
    }
  });
}
