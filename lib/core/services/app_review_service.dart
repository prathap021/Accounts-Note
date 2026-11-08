import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../providers/settings_provider.dart';
import '../constants/app_constants.dart';
import '../utils/app_log.dart';

final appReviewServiceProvider = Provider<AppReviewService>((ref) {
  return AppReviewService(prefs: ref.watch(sharedPreferencesProvider));
});

/// The store's rating sheet, behind an interface so the prompting rules can
/// be tested.
abstract class StoreReview {
  Future<bool> isAvailable();
  Future<void> requestReview();
  Future<void> openStoreListing({String? appStoreId});
}

class InAppStoreReview implements StoreReview {
  const InAppStoreReview();

  @override
  Future<bool> isAvailable() => InAppReview.instance.isAvailable();

  @override
  Future<void> requestReview() => InAppReview.instance.requestReview();

  @override
  Future<void> openStoreListing({String? appStoreId}) =>
      InAppReview.instance.openStoreListing(appStoreId: appStoreId);
}

/// Asks for a rating at good moments, and rarely.
///
/// The prompt comes right after a transaction is saved, the moment the app
/// has just been useful: on the 5th, the 30th and the 100th entry, and never
/// twice within 60 days. Both stores also limit how often their sheet
/// actually appears, so a request is a hint, not a guarantee.
class AppReviewService {
  AppReviewService({
    required this.prefs,
    this.review = const InAppStoreReview(),
    this.clock = DateTime.now,
  });

  final SharedPreferences prefs;
  final StoreReview review;
  final DateTime Function() clock;

  static const _countKey = 'tx_count_for_review';
  static const _lastAskedKey = 'review_last_requested';
  static const milestones = {5, 30, 100};
  static const minGap = Duration(days: 60);

  /// Call after each transaction the user adds.
  Future<void> recordTransactionAdded() async {
    try {
      final count = (prefs.getInt(_countKey) ?? 0) + 1;
      await prefs.setInt(_countKey, count);
      if (!milestones.contains(count)) return;

      final lastMs = prefs.getInt(_lastAskedKey);
      final now = clock();
      if (lastMs != null &&
          now.difference(DateTime.fromMillisecondsSinceEpoch(lastMs)) <
              minGap) {
        return;
      }
      if (!await review.isAvailable()) return;
      await prefs.setInt(_lastAskedKey, now.millisecondsSinceEpoch);
      await review.requestReview();
    } catch (e) {
      // A rating prompt must never get in the way of saving a transaction.
      appLog('Review request skipped: $e');
    }
  }

  /// "Rate Accounts Note" in Settings: the app's store page, where the user
  /// can rate and review whenever they like.
  Future<void> openStorePage() =>
      review.openStoreListing(appStoreId: AppLinks.appStoreId);
}
