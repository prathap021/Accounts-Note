import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppReviewService {
  static final InAppReview _inAppReview = InAppReview.instance;

  static Future<void> checkAndAskForReview() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      int txCount = prefs.getInt('tx_count_for_review') ?? 0;
      txCount++;
      await prefs.setInt('tx_count_for_review', txCount);

      if (txCount == 3 || txCount == 10 || txCount == 50) {
        if (await _inAppReview.isAvailable()) {
          await _inAppReview.requestReview();
        }
      }
    } catch (e) {
      // ignore
    }
  }
}
