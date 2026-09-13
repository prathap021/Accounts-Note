import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart' as cf;
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/app_constants.dart';
import '../../core/utils/result.dart';
import '../../models/app_user_model.dart';

class ContributionRepository {
  final FirebaseFirestore _firestore;
  final cf.FirebaseFunctions _functions;

  ContributionRepository({
    FirebaseFirestore? firestore,
    cf.FirebaseFunctions? functions,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _functions = functions ?? cf.FirebaseFunctions.instance;

  Stream<AppUserModel?> watchProfile(String uid) {
    return _firestore
        .collection(FirestoreCollections.users)
        .doc(uid)
        .snapshots()
        .map((snap) => snap.exists ? AppUserModel.fromDoc(snap) : null);
  }

  /// Starts Stripe Checkout for a one-time contribution (USD).
  Future<Result<void>> startContribution(double amountUsd) async {
    if (amountUsd < ContributionPricing.minUsd) {
      return Result.failure(
        AppFailure(
          'Minimum contribution is \$${ContributionPricing.minUsd.toStringAsFixed(0)}.',
          code: 'min-amount',
        ),
      );
    }
    try {
      final callable = _functions.httpsCallable('createContributionCheckout');
      final result = await callable.call(<String, dynamic>{
        'amountUsd': amountUsd,
      });
      final url = (result.data as Map)['url'] as String?;
      if (url == null || url.isEmpty) {
        return Result.failure(
          AppFailure('Could not start checkout. Try again.', code: 'no-url'),
        );
      }
      final ok = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (!ok) {
        return Result.failure(
          AppFailure('Could not open Stripe Checkout.', code: 'launch-failed'),
        );
      }
      return Result.success(null);
    } on cf.FirebaseFunctionsException catch (e) {
      return Result.failure(
        AppFailure(e.message ?? 'Checkout failed.', code: e.code),
      );
    } catch (e) {
      return Result.failure(AppFailure.fromException(e));
    }
  }
}

/// Whether the user may create another transaction today.
class TransactionEntitlement {
  final bool allowed;
  final bool isUnlocked;
  final int usedToday;
  final int dailyLimit;
  final String? message;

  const TransactionEntitlement({
    required this.allowed,
    required this.isUnlocked,
    required this.usedToday,
    required this.dailyLimit,
    this.message,
  });

  int get remaining =>
      isUnlocked ? -1 : (dailyLimit - usedToday).clamp(0, dailyLimit);
}
