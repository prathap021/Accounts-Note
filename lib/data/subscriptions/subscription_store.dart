import 'dart:async';
import 'dart:io' show Platform;

import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart'
    show ReplacementMode;
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:uuid/uuid.dart';

/// A subscription as the store sells it, with the store's own localized price.
class StoreProduct {
  final String id;
  final String title;

  /// Formatted for the user's storefront, e.g. "₹99.00".
  final String price;

  /// The plugin's own object, needed to start a purchase.
  final Object? native;

  const StoreProduct({
    required this.id,
    required this.title,
    required this.price,
    this.native,
  });
}

enum StorePurchaseStatus { pending, purchased, restored, canceled, error }

/// One purchase update from the store.
class StorePurchase {
  final String productId;
  final StorePurchaseStatus status;

  /// `android` or `ios`.
  final String platform;

  /// Google Play's purchase token on Android. What the backend verifies.
  final String? purchaseToken;

  /// The App Store transaction id on iOS. What the backend verifies.
  final String? transactionId;

  final String? errorMessage;

  /// Whether the store is still waiting for [SubscriptionStore.complete].
  final bool needsCompletion;

  final Object? native;

  const StorePurchase({
    required this.productId,
    required this.status,
    required this.platform,
    this.purchaseToken,
    this.transactionId,
    this.errorMessage,
    this.needsCompletion = false,
    this.native,
  });

  bool get isSuccessful =>
      status == StorePurchaseStatus.purchased ||
      status == StorePurchaseStatus.restored;
}

/// The device's app store, behind an interface so tests and the Patrol suite
/// can stand in a fake. The real one is [InAppPurchaseSubscriptionStore].
abstract class SubscriptionStore {
  /// False when there is no store to buy from (no Play Store on the device,
  /// purchases disabled by parental controls, a simulator without StoreKit).
  Future<bool> isAvailable();

  /// The products the store knows, by id. Ids missing from the result are not
  /// set up (or not approved) in the store yet.
  Future<Map<String, StoreProduct>> loadProducts(Set<String> ids);

  /// Every purchase update: new purchases, renewals the store re-delivers,
  /// restores, failures. Must be listened to from app start, or purchases
  /// finished while the app was closed are never verified.
  Stream<List<StorePurchase>> get purchaseUpdates;

  /// Starts the store's purchase sheet. [accountUid] ties the purchase to the
  /// signed-in account so the backend can refuse it on any other account.
  /// [replacing] is the subscription being upgraded or downgraded, which
  /// Google Play needs to switch plans in place.
  Future<bool> buy(
    StoreProduct product, {
    required String accountUid,
    StorePurchase? replacing,
    bool isUpgrade = true,
  });

  Future<void> restore({required String accountUid});

  /// Tells the store the purchase was handled. Google Play refunds a
  /// subscription that is not acknowledged within three days.
  Future<void> complete(StorePurchase purchase);

  /// The subscription this device's store account currently owns, if any.
  /// Only Google Play needs it, to switch plans.
  Future<StorePurchase?> ownedSubscription(Set<String> productIds);
}

/// The App Store wants a UUID as the account tag, so the Firebase uid is
/// turned into one, the same way every time. The backend derives the same
/// UUID to check that a purchase belongs to the account claiming it.
String appAccountTokenFor(String uid) =>
    const Uuid().v5(Namespace.url.value, 'accountsnote:$uid');

/// [SubscriptionStore] on Google Play Billing and StoreKit, through the
/// `in_app_purchase` plugin.
class InAppPurchaseSubscriptionStore implements SubscriptionStore {
  InAppPurchaseSubscriptionStore([InAppPurchase? iap])
    : _iap = iap ?? InAppPurchase.instance;

  final InAppPurchase _iap;

  static String get _platform => Platform.isIOS ? 'ios' : 'android';

  @override
  Future<bool> isAvailable() => _iap.isAvailable();

  @override
  Future<Map<String, StoreProduct>> loadProducts(Set<String> ids) async {
    final response = await _iap.queryProductDetails(ids);
    final products = <String, StoreProduct>{};
    // Google Play lists a subscription once per base plan and offer; the
    // first entry is the plain monthly base plan.
    for (final p in response.productDetails) {
      products.putIfAbsent(
        p.id,
        () => StoreProduct(id: p.id, title: p.title, price: p.price, native: p),
      );
    }
    return products;
  }

  @override
  Stream<List<StorePurchase>> get purchaseUpdates =>
      _iap.purchaseStream.map((list) => list.map(_toStorePurchase).toList());

  @override
  Future<bool> buy(
    StoreProduct product, {
    required String accountUid,
    StorePurchase? replacing,
    bool isUpgrade = true,
  }) {
    final details = product.native! as ProductDetails;
    final PurchaseParam param;
    if (Platform.isAndroid) {
      final old = replacing?.native;
      param = GooglePlayPurchaseParam(
        productDetails: details,
        // Stored by Google as obfuscatedExternalAccountId.
        applicationUserName: accountUid,
        changeSubscriptionParam: old is GooglePlayPurchaseDetails
            ? ChangeSubscriptionParam(
                oldPurchaseDetails: old,
                // Upgrades start now and charge the difference; downgrades
                // credit the unused time against the cheaper plan.
                replacementMode: isUpgrade
                    ? ReplacementMode.chargeProratedPrice
                    : ReplacementMode.withTimeProration,
              )
            : null,
      );
    } else {
      // StoreKit switches plans within a subscription group by itself.
      param = PurchaseParam(
        productDetails: details,
        applicationUserName: appAccountTokenFor(accountUid),
      );
    }
    return _iap.buyNonConsumable(purchaseParam: param);
  }

  @override
  Future<void> restore({required String accountUid}) => _iap.restorePurchases(
    applicationUserName: Platform.isIOS
        ? appAccountTokenFor(accountUid)
        : accountUid,
  );

  @override
  Future<void> complete(StorePurchase purchase) async {
    final native = purchase.native;
    if (native is PurchaseDetails && native.pendingCompletePurchase) {
      await _iap.completePurchase(native);
    }
  }

  @override
  Future<StorePurchase?> ownedSubscription(Set<String> productIds) async {
    if (!Platform.isAndroid) return null;
    final addition = _iap
        .getPlatformAddition<InAppPurchaseAndroidPlatformAddition>();
    final response = await addition.queryPastPurchases();
    for (final p in response.pastPurchases) {
      if (productIds.contains(p.productID)) return _toStorePurchase(p);
    }
    return null;
  }

  static StorePurchase _toStorePurchase(PurchaseDetails p) {
    final status = switch (p.status) {
      PurchaseStatus.pending => StorePurchaseStatus.pending,
      PurchaseStatus.purchased => StorePurchaseStatus.purchased,
      PurchaseStatus.restored => StorePurchaseStatus.restored,
      PurchaseStatus.canceled => StorePurchaseStatus.canceled,
      PurchaseStatus.error => StorePurchaseStatus.error,
    };
    final android = _platform == 'android';
    return StorePurchase(
      productId: p.productID,
      status: status,
      platform: _platform,
      purchaseToken: android ? p.verificationData.serverVerificationData : null,
      transactionId: android ? null : p.purchaseID,
      errorMessage: p.error?.message,
      needsCompletion: p.pendingCompletePurchase,
      native: p,
    );
  }
}
