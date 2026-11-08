import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart' show CollectionReference;
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:accounts_note/core/utils/result.dart';
import 'package:accounts_note/data/repositories/credit_card_repository.dart';
import 'package:accounts_note/models/credit_card_model.dart';

import '../../support/fixtures.dart';

/// Cards feed the expense form's payment picker, the Activity card filter and
/// the per-card totals.
void main() {
  late FakeFirebaseFirestore firestore;
  late CreditCardRepository repo;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repo = CreditCardRepository(firestore: firestore);
  });

  Future<CreditCardModel> add(CreditCardModel card, {String uid = testUid}) async {
    final result = await repo.addCard(uid, card);
    return result.when(
      success: (c) => c,
      failure: (f) => throw StateError(f.message),
    );
  }

  test('adds a card and hands it back with its new id', () async {
    final saved = await add(creditCardFixture(id: ''));

    expect(saved.id, isNotEmpty,
        reason: 'the expense form selects the new card by this id at once');
    expect(saved.name, 'HDFC Millennia');
    expect(await repo.watchCards(testUid).first, [saved]);
  });

  test('lists cards alphabetically, ignoring case', () async {
    await add(creditCardFixture(id: '', name: 'sbi SimplyClick'));
    await add(creditCardFixture(id: '', name: 'Amex Platinum'));
    await add(creditCardFixture(id: '', name: 'HDFC Millennia'));

    final names = (await repo.watchCards(testUid).first).map((c) => c.name);

    expect(names, ['Amex Platinum', 'HDFC Millennia', 'sbi SimplyClick']);
  });

  test('updates a card in place, including clearing its digits', () async {
    final saved = await add(creditCardFixture(id: ''));

    await repo.updateCard(
      testUid,
      saved.copyWith(name: 'HDFC Regalia', clearLast4: true),
    );
    final cards = await repo.watchCards(testUid).first;

    expect(cards, hasLength(1), reason: 'an edit must not add a second card');
    expect(cards.single.name, 'HDFC Regalia');
    expect(cards.single.last4, isNull);
  });

  test('deletes a card', () async {
    final saved = await add(creditCardFixture(id: ''));

    final result = await repo.deleteCard(testUid, saved.id);

    expect(result.isSuccess, isTrue);
    expect(await repo.watchCards(testUid).first, isEmpty);
  });

  test("one account never sees another's cards", () async {
    await add(creditCardFixture(id: '', name: 'Mine'));
    await add(creditCardFixture(id: '', name: 'Theirs'), uid: 'user-2');

    final mine = await repo.watchCards(testUid).first;

    expect(mine.map((c) => c.name), ['Mine']);
  });

  group('offline writes', () {
    setUp(() {
      repo = CreditCardRepository(
        firestore: firestore,
        ackTimeout: const Duration(milliseconds: 20),
      );
    });

    test('a write the server never acknowledges still counts as saved',
        () async {
      // Offline, Firestore's future never completes, but the write is
      // already in the local cache. Waiting on it would hang the form.
      await expectLater(repo.commit(Completer<void>().future), completes);
    });

    test('a rejection that arrives in time is reported', () async {
      await expectLater(
        repo.commit(Future<void>.error(StateError('permission-denied'))),
        throwsStateError,
      );
    });

    test('a rejection after giving up does not escape as an uncaught error',
        () async {
      final write = Completer<void>();
      await repo.commit(write.future);

      write.completeError(StateError('rejected late'));
      // Let the late error propagate; an unhandled one fails this test.
      await Future<void>.delayed(const Duration(milliseconds: 10));
    });

    test('addCard surfaces a failure rather than throwing', () async {
      final result = await CreditCardRepository(firestore: _ThrowingFirestore())
          .addCard(testUid, creditCardFixture(id: ''));

      expect(result, isA<Failure<CreditCardModel>>());
    });
  });
}

/// Any collection access fails, the way a misconfigured Firestore would.
class _ThrowingFirestore extends FakeFirebaseFirestore {
  @override
  CollectionReference<Map<String, dynamic>> collection(String path) =>
      throw StateError('unavailable');
}
