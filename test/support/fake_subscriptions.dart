import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart' as cf;
import 'package:income_expense_tracker/core/constants/app_constants.dart';
import 'package:income_expense_tracker/core/utils/result.dart';
import 'package:income_expense_tracker/data/repositories/subscription_repository.dart';
import 'package:income_expense_tracker/data/subscriptions/subscription_store.dart';
import 'package:income_expense_tracker/models/subscription_plan.dart';

/// Shared by the widget tests (test/) and the Patrol suite (patrol_test/).

/// An app store that sells the three plans and answers purchases at once.
///
/// [nextOutcome] decides what the next [buy] reports, so a test can walk the
/// cancelled, failed and pending paths as well as the happy one.
class FakeSubscriptionStore implements SubscriptionStore {
  bool available = true;
  StorePurchaseStatus nextOutcome = StorePurchaseStatus.purchased;

  /// Product ids passed to [buy], in order.
  final List<String> bought = [];

  /// The subscription each [buy] replaced (null for a first purchase).
  final List<StorePurchase?> replaced = [];
  final List<StorePurchase> completed = [];
  int restoreCalls = 0;

  final _updates = StreamController<List<StorePurchase>>.broadcast();
  StorePurchase? _owned;
  var _nextToken = 1;

  /// Makes the store hold a subscription already. [acknowledged] is the
  /// usual case (a reinstall, a second device); an unacknowledged one is a
  /// purchase the app was killed before confirming.
  void own(SubscriptionPlan plan, {bool acknowledged = true}) {
    final p = _purchase(plan.productId!, StorePurchaseStatus.purchased);
    _owned = StorePurchase(
      productId: p.productId,
      status: p.status,
      platform: p.platform,
      purchaseToken: p.purchaseToken,
      needsCompletion: !acknowledged,
    );
  }

  StorePurchase _purchase(String productId, StorePurchaseStatus status) =>
      StorePurchase(
        productId: productId,
        status: status,
        platform: 'android',
        purchaseToken: 'token-${_nextToken++}',
        needsCompletion: status != StorePurchaseStatus.pending,
      );

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<Map<String, StoreProduct>> loadProducts(Set<String> ids) async => {
    for (final p in SubscriptionPlan.paid)
      if (ids.contains(p.productId))
        p.productId!: StoreProduct(
          id: p.productId!,
          title: p.title,
          price: '${p.priceLabel}.00',
        ),
  };

  @override
  Stream<List<StorePurchase>> get purchaseUpdates => _updates.stream;

  @override
  Future<bool> buy(
    StoreProduct product, {
    required String accountUid,
    StorePurchase? replacing,
    bool isUpgrade = true,
  }) async {
    bought.add(product.id);
    replaced.add(replacing);
    final purchase = _purchase(product.id, nextOutcome);
    if (nextOutcome == StorePurchaseStatus.purchased) _owned = purchase;
    scheduleMicrotask(() => _updates.add([purchase]));
    return true;
  }

  @override
  Future<void> restore({required String accountUid}) async {
    restoreCalls++;
    final owned = _owned;
    if (owned == null) return;
    _updates.add([
      StorePurchase(
        productId: owned.productId,
        status: StorePurchaseStatus.restored,
        platform: owned.platform,
        purchaseToken: owned.purchaseToken,
        needsCompletion: true,
      ),
    ]);
  }

  @override
  Future<void> complete(StorePurchase purchase) async {
    completed.add(purchase);
  }

  @override
  Future<StorePurchase?> ownedSubscription(Set<String> productIds) async =>
      _owned;
}

/// The backend's verifier, without Cloud Functions: a verified purchase
/// writes the plan to the profile the way `verifySubscription` does.
class FakeSubscriptionBackend extends SubscriptionRepository {
  FakeSubscriptionBackend({required this.firestore, required this.currentUid})
    : super(functions: _NoFunctions());

  final FirebaseFirestore firestore;
  final String? Function() currentUid;

  final List<StorePurchase> verified = [];
  int refreshCalls = 0;

  /// When set, the next [verify] fails with it (once).
  SubscriptionFailure? rejectNext;

  @override
  Future<Result<void>> verify(StorePurchase purchase) async {
    final reject = rejectNext;
    if (reject != null) {
      rejectNext = null;
      return Result.failure(reject);
    }
    final uid = currentUid();
    final plan = SubscriptionPlan.fromProductId(purchase.productId);
    if (uid == null || plan == null) {
      return Result.failure(const SubscriptionFailure('Not signed in.'));
    }
    await grant(uid, plan);
    verified.add(purchase);
    return Result.success(null);
  }

  @override
  Future<Result<void>> refresh() async {
    refreshCalls++;
    return Result.success(null);
  }

  /// Writes [plan] to the profile as the backend would after verifying.
  Future<void> grant(
    String uid,
    SubscriptionPlan plan, {
    String status = 'active',
    Duration validFor = const Duration(days: 30),
    bool autoRenewing = true,
  }) {
    return firestore.collection(FirestoreCollections.users).doc(uid).set({
      'subscriptionPlan': plan.name,
      'subscriptionStatus': status,
      'subscriptionExpiresAt': Timestamp.fromDate(DateTime.now().add(validFor)),
      'subscriptionAutoRenewing': autoRenewing,
      'subscriptionPlatform': 'android',
      'subscriptionProductId': plan.productId,
      'subscriptionLinkId': 'android_test',
    }, SetOptions(merge: true));
  }
}

class _NoFunctions implements cf.FirebaseFunctions {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('No Cloud Functions in tests');
}
