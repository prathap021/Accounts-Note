/// How often a paid plan renews.
enum BillingPeriod {
  monthly('Monthly', 'month'),
  yearly('Yearly', 'year');

  const BillingPeriod(this.label, this.unit);

  final String label;

  /// "month" / "year", as in "$1 / month".
  final String unit;
}

/// What a user may add per day, by the plan they are on.
///
/// One allowance for every entry, income and expense alike: the user can
/// spend it all on expenses, all on income, or any mix. Each plan can be
/// paid monthly or yearly; the allowance is the same either way.
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
    yearlyProductId: null,
    priceLabel: '\$0',
    inrPriceLabel: '₹0',
    yearlyPriceLabel: '\$0',
    inrYearlyPriceLabel: '₹0',
    dailyLimit: 14,
  ),
  basic(
    title: 'Basic',
    productId: 'accounts_note_basic_monthly',
    yearlyProductId: 'accounts_note_basic_yearly',
    priceLabel: '\$1',
    inrPriceLabel: '₹99',
    yearlyPriceLabel: '\$11',
    inrYearlyPriceLabel: '₹1,089',
    dailyLimit: 60,
  ),
  standard(
    title: 'Standard',
    productId: 'accounts_note_standard_monthly',
    yearlyProductId: 'accounts_note_standard_yearly',
    priceLabel: '\$2',
    inrPriceLabel: '₹199',
    yearlyPriceLabel: '\$23',
    inrYearlyPriceLabel: '₹2,289',
    dailyLimit: 120,
  ),
  premium(
    title: 'Premium',
    productId: 'accounts_note_premium_monthly',
    yearlyProductId: 'accounts_note_premium_yearly',
    priceLabel: '\$3',
    inrPriceLabel: '₹299',
    yearlyPriceLabel: '\$35',
    inrYearlyPriceLabel: '₹3,489',
    dailyLimit: 200,
  );

  const SubscriptionPlan({
    required this.title,
    required this.productId,
    required this.yearlyProductId,
    required this.priceLabel,
    required this.inrPriceLabel,
    required this.yearlyPriceLabel,
    required this.inrYearlyPriceLabel,
    required this.dailyLimit,
  });

  final String title;

  /// The monthly auto-renewing subscription in Google Play and App Store
  /// Connect. Both stores use the same id. Null for [free].
  final String? productId;

  /// The yearly one, priced at twelve months less $1 (₹99 in India).
  final String? yearlyProductId;

  /// The monthly list price in US dollars. Shown when the store's own
  /// localized price is not available (no store on the device, or products
  /// not loaded yet); otherwise the store's price is shown, so set the same
  /// prices in Google Play and App Store Connect.
  final String priceLabel;

  /// The monthly list price in India.
  final String inrPriceLabel;

  /// The yearly list prices: 12 × monthly, less $1 / ₹99.
  final String yearlyPriceLabel;
  final String inrYearlyPriceLabel;

  /// What a yearly plan saves over twelve monthly payments, by list price.
  static String yearlySaving(String currency) =>
      currency == 'INR' ? '₹99' : '\$1';

  /// Entries (income and expense together) allowed per day.
  final int dailyLimit;

  /// A month's worth, as plans are presented: the daily cap over 30 days.
  /// The limit itself is applied per day.
  static const daysPerMonth = 30;

  int get monthlyLimit => dailyLimit * daysPerMonth;

  /// The three plans that can be bought, cheapest first.
  static const paid = [basic, standard, premium];

  String? productIdFor(BillingPeriod period) => switch (period) {
    BillingPeriod.monthly => productId,
    BillingPeriod.yearly => yearlyProductId,
  };

  /// The list price for someone keeping accounts in [currency]: rupees for
  /// INR, US dollars for everything else. Only shown until the store's own
  /// localized price has loaded.
  String listPrice(
    String currency, [
    BillingPeriod period = BillingPeriod.monthly,
  ]) {
    final inr = currency == 'INR';
    return switch (period) {
      BillingPeriod.monthly => inr ? inrPriceLabel : priceLabel,
      BillingPeriod.yearly => inr ? inrYearlyPriceLabel : yearlyPriceLabel,
    };
  }

  /// Every store product id (monthly and yearly), for querying the store.
  static Set<String> get productIds => {
    for (final p in paid) ...[p.productId!, p.yearlyProductId!],
  };

  bool get isPaid => this != free;

  /// Higher plans allow more per day, so moving to one is an upgrade.
  bool isHigherThan(SubscriptionPlan other) => index > other.index;

  static SubscriptionPlan? fromProductId(String? productId) {
    for (final p in paid) {
      if (p.productId == productId || p.yearlyProductId == productId) {
        return p;
      }
    }
    return null;
  }

  /// Whether [productId] is a monthly or a yearly product. Monthly when
  /// unknown.
  static BillingPeriod periodOf(String? productId) {
    for (final p in paid) {
      if (p.yearlyProductId == productId) return BillingPeriod.yearly;
    }
    return BillingPeriod.monthly;
  }

  static SubscriptionPlan fromName(String? name) =>
      values.firstWhere((p) => p.name == name, orElse: () => free);
}
