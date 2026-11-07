import '../core/constants/app_constants.dart';

/// What a user may add per day, by the plan they are on.
///
/// Income and expense are capped separately: a busy day of spending never
/// eats into the entries left for income, and the other way round.
///
/// The same numbers live in three places that must agree:
/// - here, for the app's own check and the plan screen,
/// - `dailyLimit()` in `firestore.rules`, which is what actually refuses a
///   write past the limit,
/// - `PLAN_BY_PRODUCT` in `functions/src/subscriptions.ts`, which maps a
///   store product to the plan written on the user's profile.
enum SubscriptionPlan {
  free(
    title: 'Free',
    productId: null,
    priceLabel: '₹0',
    dailyIncomeLimit: 7,
    dailyExpenseLimit: 7,
  ),
  basic(
    title: 'Basic',
    productId: 'accounts_note_basic_monthly',
    priceLabel: '₹99',
    dailyIncomeLimit: 30,
    dailyExpenseLimit: 30,
  ),
  standard(
    title: 'Standard',
    productId: 'accounts_note_standard_monthly',
    priceLabel: '₹199',
    dailyIncomeLimit: 60,
    dailyExpenseLimit: 60,
  ),
  premium(
    title: 'Premium',
    productId: 'accounts_note_premium_monthly',
    priceLabel: '₹299',
    dailyIncomeLimit: 100,
    dailyExpenseLimit: 100,
  );

  const SubscriptionPlan({
    required this.title,
    required this.productId,
    required this.priceLabel,
    required this.dailyIncomeLimit,
    required this.dailyExpenseLimit,
  });

  final String title;

  /// The monthly auto-renewing subscription in Google Play and App Store
  /// Connect. Both stores use the same id. Null for [free].
  final String? productId;

  /// Shown when the store's own localized price is not available (no store
  /// on the device, or products not loaded yet).
  final String priceLabel;

  final int dailyIncomeLimit;
  final int dailyExpenseLimit;

  /// The three plans that can be bought, cheapest first.
  static const paid = [basic, standard, premium];

  /// Every store product id, for querying the store.
  static Set<String> get productIds => {for (final p in paid) p.productId!};

  int limitFor(TransactionType type) => switch (type) {
    TransactionType.income => dailyIncomeLimit,
    TransactionType.expense => dailyExpenseLimit,
  };

  bool get isPaid => this != free;

  /// Higher plans allow more per day, so moving to one is an upgrade.
  bool isHigherThan(SubscriptionPlan other) => index > other.index;

  static SubscriptionPlan? fromProductId(String? productId) {
    for (final p in paid) {
      if (p.productId == productId) return p;
    }
    return null;
  }

  static SubscriptionPlan fromName(String? name) =>
      values.firstWhere((p) => p.name == name, orElse: () => free);
}
