/// Central place for magic strings, Firestore collection names, and
/// static configuration so nothing is hard-coded across the codebase.
class FirestoreCollections {
  static const users = 'users';
  static const transactions = 'transactions';
  static const categories = 'categories';
  static const budgets = 'budgets';
  static const recurringTransactions = 'recurringTransactions';
  static const settings = 'settings';
  static const notifications = 'notifications';
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

  static String recurring(String uid) =>
      '${user(uid)}/${FirestoreCollections.recurringTransactions}';

  static String settings(String uid) =>
      '${user(uid)}/${FirestoreCollections.settings}/preferences';
}

enum TransactionType { income, expense }

/// User access tier — separate from income/expense transaction types.
/// Contribution marks the user as a [contributor]; it is never logged as a
/// transaction in the ledger.
enum UserAccessTier { free, contributor }

enum RecurrenceFrequency { daily, weekly, monthly, yearly }

class AppDefaults {
  static const defaultCurrency = 'INR';
  static const pageSize = 20; // transactions fetched per pagination page
  static const financialMonthStartDay = 1;

  /// After this many lifetime income+expense creates, the optional
  /// contribution dialog becomes eligible (does not block transactions).
  static const contributionPromptTransactionThreshold = 7;

  /// @Deprecated Use [contributionPromptTransactionThreshold].
  static const freeDailyTransactionLimit = contributionPromptTransactionThreshold;
}

/// Optional one-time contribution (USD) — user-tier support, not a ledger entry.
class ContributionPricing {
  static const minUsd = 5.0;
  static const presetUsd = <double>[5, 10, 25];
  static const currency = 'usd';
  static const successDeepLink = 'accountsnote://stripe-success';
  static const cancelDeepLink = 'accountsnote://stripe-cancel';
}

const List<Map<String, dynamic>> kDefaultExpenseCategories = [
  {'name': 'Food', 'icon': 'restaurant', 'color': 0xFFEF6C00},
  {'name': 'Transport', 'icon': 'directions_car', 'color': 0xFF1E88E5},
  {'name': 'Shopping', 'icon': 'shopping_bag', 'color': 0xFFD81B60},
  {'name': 'Bills', 'icon': 'receipt_long', 'color': 0xFF6D4C41},
  {'name': 'Entertainment', 'icon': 'movie', 'color': 0xFF8E24AA},
  {'name': 'Health', 'icon': 'local_hospital', 'color': 0xFFE53935},
  {'name': 'Education', 'icon': 'school', 'color': 0xFF3949AB},
  {'name': 'Other', 'icon': 'category', 'color': 0xFF757575},
];

const List<Map<String, dynamic>> kDefaultIncomeCategories = [
  {'name': 'Salary', 'icon': 'work', 'color': 0xFF2E7D32},
  {'name': 'Business', 'icon': 'store', 'color': 0xFF00897B},
  {'name': 'Investment', 'icon': 'trending_up', 'color': 0xFF43A047},
  {'name': 'Other', 'icon': 'category', 'color': 0xFF757575},
];
