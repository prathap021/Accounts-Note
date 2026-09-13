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
        _functions = functions ??
            cf.FirebaseFunctions.instanceFor(region: 'us-central1');

  Stream<AppUserModel?> watchProfile(String uid) {
    return _firestore
        .collection(FirestoreCollections.users)
        .doc(uid)
        .snapshots()
        .map((snap) => snap.exists ? AppUserModel.fromDoc(snap) : null);
  }

  static String todayKey([DateTime? now]) {
    final n = now ?? DateTime.now();
    final m = n.month.toString().padLeft(2, '0');
    final d = n.day.toString().padLeft(2, '0');
    return '${n.year}-$m-$d';
  }

  /// Records that the contribution dialog was shown (and optionally declined).
  /// Suppresses further prompts for the rest of the calendar day.
  Future<Result<void>> markContributionPromptHandled(
    String uid, {
    required bool declined,
  }) async {
    try {
      final today = todayKey();
      final data = <String, dynamic>{
        'contributionPromptLastShownDate': today,
      };
      if (declined) {
        data['contributionDeclinedDate'] = today;
      }
      await _firestore.collection(FirestoreCollections.users).doc(uid).update(data);
      return Result.success(null);
    } catch (e) {
      return Result.failure(AppFailure.fromException(e));
    }
  }

  /// Starts Stripe Checkout for a financial contribution (USD).
  Future<Result<void>> startContribution(
    double amountUsd, {
    String supportType = 'one_time',
    String? featureNote,
  }) async {
    if (amountUsd < ContributionPricing.minUsd) {
      return Result.failure(
        AppFailure(
          'Minimum contribution is \$${ContributionPricing.minUsd.toStringAsFixed(0)}.',
          code: 'min-amount',
        ),
      );
    }
    try {
      final callable = _functions.httpsCallable(
        'createContributionCheckout',
        options: cf.HttpsCallableOptions(timeout: const Duration(seconds: 60)),
      );
      final payload = <String, dynamic>{
        'amountUsd': amountUsd,
        'supportType': supportType,
      };
      if (featureNote != null && featureNote.trim().isNotEmpty) {
        payload['featureNote'] = featureNote.trim();
      }
      final result = await callable.call(payload);
      final raw = result.data;
      final map = raw is Map ? Map<Object?, Object?>.from(raw) : null;
      final url = map?['url']?.toString();
      if (url == null || url.isEmpty) {
        return Result.failure(
          const AppFailure(
            'Could not start checkout. Try again.',
            code: 'no-url',
          ),
        );
      }
      final uri = Uri.parse(url);
      var launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        launched = await launchUrl(uri, mode: LaunchMode.platformDefault);
      }
      if (!launched) {
        return Result.failure(
          const AppFailure(
            'Could not open Stripe Checkout in the browser.',
            code: 'launch-failed',
          ),
        );
      }
      return Result.success(null);
    } on cf.FirebaseFunctionsException catch (e) {
      final detail = e.message?.trim();
      return Result.failure(
        AppFailure(
          detail != null && detail.isNotEmpty
              ? detail
              : 'Checkout failed (${e.code}). Please try again.',
          code: e.code,
        ),
      );
    } catch (e) {
      return Result.failure(AppFailure.fromException(e));
    }
  }
}
