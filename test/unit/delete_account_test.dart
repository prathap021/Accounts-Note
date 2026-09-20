import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:income_expense_tracker/data/repositories/auth_repository.dart';

import '../support/fixtures.dart';

/// Account deletion for both sign-up routes.
///
/// The previous implementation threw unconditionally for email/password
/// accounts, so those users could never close their account at all.
void main() {
  late FakeFirebaseFirestore firestore;

  setUp(() async {
    firestore = FakeFirebaseFirestore();
  });

  Future<void> seedUserData(String uid) async {
    await firestore.collection('users').doc(uid).set({'displayName': 'A'});
    await firestore
        .collection('users')
        .doc(uid)
        .collection('transactions')
        .doc('tx-1')
        .set(txFixture().toMap());
  }

  AuthRepository repoFor(MockUser user) {
    return AuthRepository(
      auth: MockFirebaseAuth(signedIn: true, mockUser: user),
      firestore: firestore,
    );
  }

  MockUser emailUser() => MockUser(
        uid: 'email-uid',
        email: 'a.person@example.com',
        isEmailVerified: true,
      );

  test('reports a clear failure when nobody is signed in', () async {
    final repo = AuthRepository(
      auth: MockFirebaseAuth(signedIn: false),
      firestore: firestore,
    );

    final result = await repo.deleteAccount();

    final failure = result.when(success: (_) => null, failure: (f) => f);
    expect(failure, isNotNull);
    expect(failure!.code, 'no-user');
  });

  test('an email/password account can be deleted', () async {
    final user = emailUser();
    await seedUserData(user.uid);
    final repo = repoFor(user);

    final result = await repo.deleteAccount();

    final failure = result.when(success: (_) => null, failure: (f) => f);
    expect(result.isSuccess, isTrue,
        reason: 'email sign-ups must be able to close their account. '
            'Got: ${failure?.code} / ${failure?.message} / ${failure?.cause}');
  });

  test('cloud data is removed', () async {
    final user = emailUser();
    await seedUserData(user.uid);
    final repo = repoFor(user);

    await repo.deleteAccount();

    final doc = await firestore.collection('users').doc(user.uid).get();
    expect(doc.exists, isFalse, reason: 'the user document is gone');

    final txs = await firestore
        .collection('users')
        .doc(user.uid)
        .collection('transactions')
        .get();
    expect(txs.docs, isEmpty, reason: 'subcollections go with it');
  });

  test('deleting with no data to remove still succeeds', () async {
    final repo = repoFor(emailUser());
    final result = await repo.deleteAccount();
    expect(result.isSuccess, isTrue);
  });
}
