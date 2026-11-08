import 'package:cloud_functions/cloud_functions.dart' as cf;
import 'package:flutter_test/flutter_test.dart';
import 'package:accounts_note/data/repositories/subscription_repository.dart';
import 'package:accounts_note/data/subscriptions/subscription_store.dart';

class _FailingCallable implements cf.HttpsCallable {
  _FailingCallable(this.code);
  final String code;

  @override
  Future<cf.HttpsCallableResult<T>> call<T>([dynamic parameters]) =>
      throw cf.FirebaseFunctionsException(code: code, message: 'from $code');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Functions implements cf.FirebaseFunctions {
  _Functions(this.code);
  final String code;

  @override
  cf.HttpsCallable httpsCallable(
    String name, {
    cf.HttpsCallableOptions? options,
  }) => _FailingCallable(code);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _purchase = StorePurchase(
  productId: 'accounts_note_basic_monthly',
  status: StorePurchaseStatus.purchased,
  platform: 'android',
  purchaseToken: 'token',
);

/// Whether a failed verification lets the store keep the purchase.
void main() {
  Future<SubscriptionFailure> failureFor(String code) async {
    final repo = SubscriptionRepository(functions: _Functions(code));
    final result = await repo.verify(_purchase);
    return result.when(
      success: (_) => fail('expected a failure'),
      failure: (f) => f as SubscriptionFailure,
    );
  }

  test('a function that is not deployed is retried, never final', () async {
    final f = await failureFor('not-found');
    expect(
      f.isFinal,
      isFalse,
      reason: 'confirming it would let Google keep the money for no plan',
    );
  });

  test('a server that is not set up is retried', () async {
    expect((await failureFor('failed-precondition')).isFinal, isFalse);
    expect((await failureFor('unavailable')).isFinal, isFalse);
    expect((await failureFor('internal')).isFinal, isFalse);
  });

  test(
    'a purchase the store rejects, or another account owns, is final',
    () async {
      expect((await failureFor('invalid-argument')).isFinal, isTrue);
      expect((await failureFor('already-exists')).isFinal, isTrue);
      expect((await failureFor('permission-denied')).isFinal, isTrue);
    },
  );
}
