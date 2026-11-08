import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:accounts_note/core/constants/app_constants.dart';
import 'package:accounts_note/models/credit_card_model.dart';

import '../../support/fixtures.dart';

/// A card is how expenses get grouped per credit card, and the one place the
/// app touches card numbers — so what it may hold is pinned down here.
void main() {
  group('cloud serialization', () {
    test('round-trips every field through Firestore', () async {
      final firestore = FakeFirebaseFirestore();
      final ref = firestore.collection(FirestorePaths.creditCards(testUid)).doc('c1');
      await ref.set(creditCardFixture(creditLimit: 150000).toMap());

      final restored = CreditCardModel.fromDoc(await ref.get());

      expect(restored.id, 'c1');
      expect(restored.name, 'HDFC Millennia');
      expect(restored.last4, '4321');
      expect(restored.color, 0xFF1E3A8A);
      expect(restored.creditLimit, 150000);
      expect(restored.createdAt, fixedNow);
    });

    test('keeps the optional fields null rather than inventing values',
        () async {
      final firestore = FakeFirebaseFirestore();
      final ref = firestore.collection(FirestorePaths.creditCards(testUid)).doc('c2');
      await ref.set(creditCardFixture(last4: null).toMap());

      final restored = CreditCardModel.fromDoc(await ref.get());

      expect(restored.last4, isNull);
      expect(restored.creditLimit, isNull);
    });

    test('stores only the last four digits — no number, expiry or CVV keys',
        () {
      expect(
        creditCardFixture().toMap().keys,
        unorderedEquals(['name', 'last4', 'color', 'creditLimit', 'createdAt']),
        reason: 'firestore.rules refuses any other field, so this must match',
      );
    });
  });

  group('displayName', () {
    test('adds the last four digits so two cards from one bank differ', () {
      expect(creditCardFixture().displayName, 'HDFC Millennia ••4321');
    });

    test('is just the name when no digits were given', () {
      expect(creditCardFixture(last4: null).displayName, 'HDFC Millennia');
    });
  });

  group('isValidLast4', () {
    test('accepts exactly four digits', () {
      expect(CreditCardModel.isValidLast4('0042'), isTrue);
    });

    test('refuses anything else, including a full card number', () {
      for (final value in ['', '123', '12345', '12a4', '4111111111111111']) {
        expect(CreditCardModel.isValidLast4(value), isFalse, reason: value);
      }
    });
  });

  group('containsCardNumber', () {
    test('catches a full number however it is spaced', () {
      for (final name in [
        'Visa 4111111111111111',
        'Visa 4111 1111 1111 1111',
        'Visa 4111-1111-1111-1111',
      ]) {
        expect(CreditCardModel.containsCardNumber(name), isTrue, reason: name);
      }
    });

    test('lets ordinary names with a few digits through', () {
      for (final name in ['HDFC Regalia 2024', 'Amex Platinum', 'Card 4321']) {
        expect(CreditCardModel.containsCardNumber(name), isFalse, reason: name);
      }
    });
  });

  group('copyWith', () {
    test('can clear the optional fields, which passing null cannot', () {
      final card = creditCardFixture(creditLimit: 50000);

      expect(card.copyWith(last4: null).last4, '4321');
      expect(card.copyWith(clearLast4: true).last4, isNull);
      expect(card.copyWith(clearCreditLimit: true).creditLimit, isNull);
    });

    test('never changes when the card was added', () {
      expect(creditCardFixture().copyWith(name: 'Renamed').createdAt, fixedNow);
    });
  });
}
