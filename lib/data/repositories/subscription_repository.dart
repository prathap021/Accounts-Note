import 'package:cloud_functions/cloud_functions.dart' as cf;

import '../../core/utils/result.dart';
import '../subscriptions/subscription_store.dart';

/// Why a purchase could not be verified.
class SubscriptionFailure extends AppFailure {
  /// True when retrying cannot help (the purchase belongs to another account,
  /// it has expired, the product is unknown). The store is then told the
  /// purchase was handled, so it stops re-delivering it.
  final bool isFinal;

  const SubscriptionFailure(super.message, {super.code, this.isFinal = false});
}

/// The backend's side of subscriptions: proving a purchase with the store
/// and writing the resulting plan to the user's profile.
///
/// The app never writes its own plan. It hands the store's proof to the
/// `verifySubscription` Cloud Function, which checks it with Google Play or
/// the App Store and updates `users/{uid}`. The profile stream then carries
/// the new plan back to every screen.
class SubscriptionRepository {
  SubscriptionRepository({cf.FirebaseFunctions? functions})
    : _functions =
          functions ?? cf.FirebaseFunctions.instanceFor(region: 'us-central1');

  final cf.FirebaseFunctions _functions;

  /// Codes the Cloud Function uses for a purchase that will never verify.
  ///
  /// Not `not-found`: that is also what a function that has not been
  /// deployed returns, and a purchase must never be confirmed to the store
  /// (and so kept by Google) when nothing has granted the plan for it.
  /// Likewise `failed-precondition`, which means the server is not set up.
  static const _finalCodes = {
    'already-exists',
    'invalid-argument',
    'permission-denied',
  };

  Future<Result<void>> verify(
    StorePurchase purchase,
  ) => _call('verifySubscription', {
    'platform': purchase.platform,
    'productId': purchase.productId,
    if (purchase.purchaseToken != null) 'purchaseToken': purchase.purchaseToken,
    if (purchase.transactionId != null) 'transactionId': purchase.transactionId,
  });

  /// Asks the backend to re-check the subscription it already has on file,
  /// e.g. after the paid period ended and a renewal may have been missed.
  Future<Result<void>> refresh() => _call('refreshSubscription', const {});

  Future<Result<void>> _call(String name, Map<String, dynamic> data) async {
    try {
      await _functions
          .httpsCallable(
            name,
            options: cf.HttpsCallableOptions(
              timeout: const Duration(seconds: 30),
            ),
          )
          .call(data);
      return Result.success(null);
    } on cf.FirebaseFunctionsException catch (e) {
      final detail = e.message?.trim();
      return Result.failure(
        SubscriptionFailure(
          detail != null && detail.isNotEmpty
              ? detail
              : 'Could not confirm the subscription. Please try again.',
          code: e.code,
          isFinal: _finalCodes.contains(e.code),
        ),
      );
    } catch (e) {
      return Result.failure(
        const SubscriptionFailure(
          'Could not reach the server to confirm the subscription. '
          'It will be checked again the next time the app opens.',
          code: 'unavailable',
        ),
      );
    }
  }
}
