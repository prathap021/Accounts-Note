/// Central place for magic strings, Firestore collection names, and
/// static configuration so nothing is hard-coded across the codebase.
class FirestoreCollections {
  static const users = 'users';
  static const transactions = 'transactions';
  static const categories = 'categories';
  static const budgets = 'budgets';
  static const creditCards = 'creditCards';
  static const accounts = 'accounts';
  static const transfers = 'transfers';
  static const recurringTransactions = 'recurringTransactions';
  static const settings = 'settings';
  static const notifications = 'notifications';

  /// Per-day entry counters, `users/{uid}/usage/{yyyy-MM-dd}`, that the
  /// security rules check before accepting a new transaction.
  static const usage = 'usage';
}

/// Every user document owns these as SUB-collections, e.g.
/// users/{uid}/transactions/{transactionId}
/// This keeps data physically isolated per-user, which makes the
/// Firestore security rules trivial and prevents cross-user leaks.
class FirestorePaths {
  static String user(String uid) => '${FirestoreCollections.users}/$uid';

  static String transactions(String uid) =>
      '${user(uid)}/${FirestoreCollections.transactions}';

  static String transaction(String uid, String txId) =>
      '${transactions(uid)}/$txId';

  static String categories(String uid) =>
      '${user(uid)}/${FirestoreCollections.categories}';

  static String category(String uid, String catId) =>
      '${categories(uid)}/$catId';

  static String budgets(String uid) =>
      '${user(uid)}/${FirestoreCollections.budgets}';

  static String budget(String uid, String budgetId) =>
      '${budgets(uid)}/$budgetId';

  static String creditCards(String uid) =>
      '${user(uid)}/${FirestoreCollections.creditCards}';

  static String accounts(String uid) =>
      '${user(uid)}/${FirestoreCollections.accounts}';
  static String transfers(String uid) =>
      '${user(uid)}/${FirestoreCollections.transfers}';
  static String recurring(String uid) =>
      '${user(uid)}/${FirestoreCollections.recurringTransactions}';

  static String usageDay(String uid, String day) =>
      '${user(uid)}/${FirestoreCollections.usage}/$day';

  static String settings(String uid) =>
      '${user(uid)}/${FirestoreCollections.settings}/preferences';
}

enum TransactionType { income, expense }

/// The payment method stored on anything charged to one of the user's credit
/// cards. Which card it was is recorded separately, in `creditCardId`, so
/// filtering on this method means "any credit card".
const kCreditCardPaymentMethod = 'Credit Card';

enum RecurrenceFrequency { daily, weekly, monthly, yearly }

class AppDefaults {
  static const defaultCurrency = 'INR';
  static const pageSize = 20; // transactions fetched per pagination page
  static const financialMonthStartDay = 1;
}

/// Public project links shown in Settings / About.
class AppLinks {
  static const githubRepo = 'https://github.com/prathap021/Accounts-Note';
  static const license = 'MIT';

  /// PRIVACY.md in the repository. Also the URL to give in Play Console and
  /// App Store Connect.
  static const privacyPolicy = '$githubRepo/blob/master/PRIVACY.md';

  /// Must match `applicationId` in android/app/build.gradle.kts.
  static const androidPackage = 'com.accountsnote.app';

  /// The app's numeric Apple ID (App Store Connect → App Information), used
  /// to open the App Store page for "Rate Accounts Note" on iOS. Until it is
  /// set, the item is hidden on iOS; Android needs nothing.
  static const String? appStoreId = null;

  /// Where the user cancels or changes a subscription. Neither store lets an
  /// app cancel on the user's behalf, so the plan screen links here.
  static String manageSubscription({
    required String platform,
    String? productId,
  }) =>
      platform == 'ios'
          ? 'https://apps.apple.com/account/subscriptions'
          : 'https://play.google.com/store/account/subscriptions'
              '?package=$androidPackage'
              '${productId == null ? '' : '&sku=$productId'}';
}

const List<Map<String, dynamic>> kDefaultExpenseCategories = [
  {'name': 'Food', 'icon': 'restaurant', 'color': 0xFFF97316},
  {'name': 'Transport', 'icon': 'directions_car', 'color': 0xFF3B82F6},
  {'name': 'Shopping', 'icon': 'shopping_bag', 'color': 0xFFEC4899},
  {'name': 'Bills', 'icon': 'receipt_long', 'color': 0xFFF59E0B},
  {'name': 'Rent', 'icon': 'home', 'color': 0xFF7C5CFC},
  {'name': 'Entertainment', 'icon': 'movie', 'color': 0xFF06B6D4},
  {'name': 'Health', 'icon': 'local_hospital', 'color': 0xFFEF4444},
  {'name': 'Education', 'icon': 'school', 'color': 0xFF6366F1},
  {'name': 'Other', 'icon': 'category', 'color': 0xFF64748B},
];

const List<Map<String, dynamic>> kDefaultIncomeCategories = [
  {'name': 'Salary', 'icon': 'work', 'color': 0xFF22C55E},
  {'name': 'Business', 'icon': 'store', 'color': 0xFF14B8A6},
  {'name': 'Freelance', 'icon': 'laptop', 'color': 0xFF0EA5E9},
  {'name': 'Gift', 'icon': 'card_giftcard', 'color': 0xFFF472B6},
  {'name': 'Investment', 'icon': 'trending_up', 'color': 0xFFEAB308},
  {'name': 'Other', 'icon': 'category', 'color': 0xFF64748B},
];
