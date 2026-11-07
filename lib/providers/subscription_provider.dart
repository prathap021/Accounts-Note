import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../core/constants/app_constants.dart';
import '../core/utils/result.dart';
import '../data/repositories/subscription_repository.dart';
import '../data/subscriptions/subscription_store.dart';
import '../models/daily_usage.dart';
import '../models/subscription_plan.dart';
import '../models/subscription_status.dart';
import 'auth_provider.dart';
import 'profile_provider.dart';
import 'sync_provider.dart';
import 'transaction_provider.dart';

final subscriptionStoreProvider = Provider<SubscriptionStore>((ref) {
  return InAppPurchaseSubscriptionStore();
});

final subscriptionRepositoryProvider = Provider<SubscriptionRepository>((ref) {
  return SubscriptionRepository();
});

/// The subscription on the user's profile, as the backend last verified it.
final subscriptionStatusProvider = Provider<SubscriptionStatus>((ref) {
  return ref.watch(userProfileProvider).asData?.value?.subscription ??
      SubscriptionStatus.none;
});

/// The plan whose daily limits apply now.
final currentPlanProvider = Provider<SubscriptionPlan>((ref) {
  return ref.watch(subscriptionStatusProvider).effectivePlan();
});

/// Today's `yyyy-MM-dd`, emitted again just after each local midnight so
/// anything showing today's allowance resets on its own.
final todayKeyProvider = StreamProvider<String>((ref) {
  final controller = StreamController<String>();
  Timer? timer;
  void emit() {
    final now = DateTime.now();
    controller.add(todayKey(now));
    final midnight = DateTime(now.year, now.month, now.day + 1);
    timer = Timer(midnight.difference(now) + const Duration(seconds: 1), emit);
  }

  emit();
  ref.onDispose(() {
    timer?.cancel();
    controller.close();
  });
  return controller.stream;
});

/// The server's count for one day: everything uploaded for it, from every
/// device the user has.
final serverUsageProvider = StreamProvider.family<DailyUsage, String>((
  ref,
  day,
) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return Stream.value(DailyUsage(day: day));
  return ref.watch(transactionRepositoryProvider).watchUsage(uid, day);
});

final _localUsageChangesProvider = StreamProvider<void>((ref) {
  return ref.watch(dailyUsageStoreProvider).changes;
});

/// What the user has used today: the server's count plus entries this device
/// has added that have not been uploaded yet.
final todayUsageProvider = Provider<DailyUsage>((ref) {
  final day = ref.watch(todayKeyProvider).asData?.value ?? todayKey();
  ref.watch(_localUsageChangesProvider);
  final server =
      ref.watch(serverUsageProvider(day)).asData?.value ?? DailyUsage(day: day);
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return server;
  return server + ref.read(dailyUsageStoreProvider).unsynced(uid, day);
});

/// The user tried to add past today's allowance for [type].
/// The user tried to add past today's allowance. [type] is what they were
/// adding; the limit itself covers income and expense together.
class DailyLimitReached extends AppFailure {
  final TransactionType type;
  final SubscriptionPlan plan;
  final int limit;

  DailyLimitReached({
    required this.type,
    required this.plan,
    required this.limit,
  }) : super(
         "You've reached today's limit of $limit entries.",
         code: 'daily-limit',
       );
}

/// Decides whether one more entry of a type fits in today's allowance.
///
/// This is the app's own check, made before anything is saved, so the user
/// hears about the limit at once and offline. The security rules make the
/// same check on upload and are what actually hold the line.
class DailyLimitChecker {
  DailyLimitChecker(this._ref);

  final Ref _ref;

  static const _waitForServer = Duration(seconds: 3);

  /// Null when another entry is allowed.
  Future<DailyLimitReached?> check(TransactionType type) async {
    final uid = _ref.read(currentUidProvider);
    if (uid == null) return null;

    // Read straight from the repositories rather than through providers:
    // a provider nothing is watching is paused and would never answer. Both
    // streams emit from the local Firestore cache first, so this works
    // offline too.
    //
    // A paid user must not be held to the free limit just because the
    // profile has not loaded yet on a cold start, hence the wait.
    SubscriptionStatus status;
    try {
      final profile = await _ref
          .read(profileRepositoryProvider)
          .watchProfile(uid)
          .first
          .timeout(_waitForServer);
      status = profile?.subscription ?? SubscriptionStatus.none;
    } catch (_) {
      status = _ref.read(subscriptionStatusProvider);
    }
    final plan = status.effectivePlan();

    final day = todayKey();
    DailyUsage server;
    try {
      server = await _ref
          .read(transactionRepositoryProvider)
          .watchUsage(uid, day)
          .first
          .timeout(_waitForServer);
    } catch (_) {
      // Offline with nothing cached: the device's own count still applies.
      server = DailyUsage(day: day);
    }
    final local = _ref.read(dailyUsageStoreProvider).unsynced(uid, day);

    // One allowance for income and expense together.
    final used = server.total + local.total;
    final limit = plan.dailyLimit;
    return used >= limit
        ? DailyLimitReached(type: type, plan: plan, limit: limit)
        : null;
  }
}

final dailyLimitCheckerProvider = Provider<DailyLimitChecker>((ref) {
  return DailyLimitChecker(ref);
});

/// A one-off message for the plan screen to show.
class SubscriptionNotice {
  final String message;
  final bool isError;

  const SubscriptionNotice(this.message, {this.isError = false});
}

@immutable
class SubscriptionUiState {
  /// Still asking the store whether it is there and what it sells.
  final bool loading;
  final bool storeAvailable;

  /// Store products by id. A plan missing here cannot be bought right now.
  final Map<String, StoreProduct> products;

  /// The plan whose purchase is in progress.
  final SubscriptionPlan? purchasing;

  /// Monthly or yearly, as chosen on the plan screen.
  final BillingPeriod period;
  final bool restoring;
  final SubscriptionNotice? notice;

  const SubscriptionUiState({
    this.loading = true,
    this.storeAvailable = false,
    this.products = const {},
    this.purchasing,
    this.restoring = false,
    this.notice,
    this.period = BillingPeriod.monthly,
  });

  bool get busy => purchasing != null || restoring;

  /// The store's localized price, or the list price in [currency] (rupees
  /// for INR, dollars otherwise) until it has loaded.
  String priceFor(
    SubscriptionPlan plan, {
    String currency = 'USD',
    BillingPeriod? period,
  }) {
    final p = period ?? this.period;
    return products[plan.productIdFor(p)]?.price ?? plan.listPrice(currency, p);
  }

  /// What paying yearly saves over twelve monthly payments: from the store's
  /// prices when both are known, otherwise the list saving ($1 / ₹99).
  String yearlySavingFor(SubscriptionPlan plan, {String currency = 'USD'}) {
    final m = products[plan.productId]?.rawPrice;
    final yearly = products[plan.yearlyProductId];
    final y = yearly?.rawPrice;
    final code = yearly?.currencyCode;
    if (m != null && y != null && code != null && m * 12 > y) {
      return NumberFormat.simpleCurrency(name: code).format(m * 12 - y);
    }
    return SubscriptionPlan.yearlySaving(currency);
  }

  SubscriptionUiState copyWith({
    bool? loading,
    bool? storeAvailable,
    Map<String, StoreProduct>? products,
    SubscriptionPlan? purchasing,
    bool clearPurchasing = false,
    bool? restoring,
    SubscriptionNotice? notice,
    BillingPeriod? period,
  }) {
    return SubscriptionUiState(
      loading: loading ?? this.loading,
      storeAvailable: storeAvailable ?? this.storeAvailable,
      products: products ?? this.products,
      purchasing: clearPurchasing ? null : (purchasing ?? this.purchasing),
      restoring: restoring ?? this.restoring,
      notice: notice ?? this.notice,
      period: period ?? this.period,
    );
  }
}

/// Buys, upgrades and restores subscriptions, and sees each purchase through
/// to the backend.
///
/// Started when the main screens open and kept for the session, because the
/// store delivers purchases whenever it likes: a renewal on launch, a
/// purchase that finished after the app was killed, a pending payment that
/// cleared. Each one is verified by the backend before the store is told it
/// was handled. Nothing here writes the plan; it arrives through the profile.
class SubscriptionController extends Notifier<SubscriptionUiState> {
  late SubscriptionStore _store;
  late SubscriptionRepository _backend;
  StreamSubscription<List<StorePurchase>>? _purchases;
  bool _restoredSomething = false;
  bool _refreshRequested = false;
  bool _periodChosen = false;

  @override
  SubscriptionUiState build() {
    _store = ref.watch(subscriptionStoreProvider);
    _backend = ref.watch(subscriptionRepositoryProvider);

    _purchases = _store.purchaseUpdates.listen(
      _onPurchases,
      onError: (Object e) => debugPrint('Purchase stream error: $e'),
    );
    ref.onDispose(() => _purchases?.cancel());

    // The paid period ran out but the store may well have renewed it: ask the
    // backend to look, once per session.
    ref.listen<SubscriptionStatus>(subscriptionStatusProvider, (_, next) {
      // Open the plan screen on the period the user already pays for.
      // Deferred: this can fire while build() is still running.
      if (!_periodChosen && next.plan.isPaid) {
        final period = SubscriptionPlan.periodOf(next.productId);
        Future.microtask(() {
          if (!_periodChosen && period != state.period) {
            state = state.copyWith(period: period);
          }
        });
      }
      if (_refreshRequested || !next.needsRefresh()) return;
      _refreshRequested = true;
      unawaited(_backend.refresh());
    }, fireImmediately: true);

    unawaited(Future.microtask(_loadStore));
    return const SubscriptionUiState();
  }

  Future<void> _loadStore() async {
    try {
      final available = await _store.isAvailable();
      final products = available
          ? await _store.loadProducts(SubscriptionPlan.productIds)
          : const <String, StoreProduct>{};
      state = state.copyWith(
        loading: false,
        storeAvailable: available,
        products: products,
      );
      if (available) await _finishUnacknowledged();
    } catch (e) {
      debugPrint('Store unavailable: $e');
      state = state.copyWith(loading: false, storeAvailable: false);
    }
  }

  /// A Google Play purchase the app never confirmed (it was killed mid-way)
  /// is not re-delivered by the purchase stream, and Play refunds it after
  /// three days. Pick it up here.
  Future<void> _finishUnacknowledged() async {
    final owned = await _store.ownedSubscription(SubscriptionPlan.productIds);
    if (owned != null && owned.needsCompletion) {
      await _onPurchases([owned]);
    }
  }

  /// The Monthly | Yearly switch on the plan screen.
  void selectPeriod(BillingPeriod period) {
    _periodChosen = true;
    state = state.copyWith(period: period);
  }

  /// Buys [plan] for the chosen [SubscriptionUiState.period]. Also how a
  /// subscriber changes plan or switches between monthly and yearly.
  Future<void> buy(SubscriptionPlan plan) async {
    final uid = ref.read(currentUidProvider);
    if (uid == null || state.busy) return;
    final period = state.period;
    final product = state.products[plan.productIdFor(period)];
    if (product == null) {
      _notify(
        state.storeAvailable
            ? 'The ${period.label.toLowerCase()} ${plan.title} plan is not '
                  'available from the store yet.'
            : 'Purchases are not available on this device.',
        isError: true,
      );
      return;
    }

    final current = ref.read(currentPlanProvider);
    final currentPeriod = SubscriptionPlan.periodOf(
      ref.read(subscriptionStatusProvider).productId,
    );
    // A bigger plan, or the same plan for a longer period, starts at once and
    // charges the difference; anything else is a downgrade.
    final isUpgrade =
        plan.isHigherThan(current) ||
        (plan == current &&
            period == BillingPeriod.yearly &&
            currentPeriod == BillingPeriod.monthly);
    state = state.copyWith(purchasing: plan);
    try {
      final replacing = current.isPaid
          ? await _store.ownedSubscription(SubscriptionPlan.productIds)
          : null;
      final started = await _store.buy(
        product,
        accountUid: uid,
        replacing: replacing,
        isUpgrade: isUpgrade,
      );
      if (!started) state = state.copyWith(clearPurchasing: true);
    } catch (e) {
      state = state.copyWith(clearPurchasing: true);
      _notify('Could not start the purchase. Please try again.', isError: true);
    }
  }

  Future<void> restore() async {
    final uid = ref.read(currentUidProvider);
    if (uid == null || state.busy) return;
    state = state.copyWith(restoring: true);
    _restoredSomething = false;
    try {
      if (state.storeAvailable) await _store.restore(accountUid: uid);
    } catch (e) {
      debugPrint('Restore failed: $e');
    }
    // Also re-check what the backend has on file. That covers a reinstall
    // on a device whose store has nothing to re-deliver.
    final refreshed = await _backend.refresh();
    state = state.copyWith(restoring: false);
    if (_restoredSomething) return;
    final active = ref.read(subscriptionStatusProvider).isActive();
    refreshed.when(
      success: (_) => _notify(
        active
            ? 'Your subscription is up to date.'
            : 'No active subscription was found for this account.',
      ),
      failure: (_) =>
          _notify('No active subscription was found for this account.'),
    );
  }

  Future<void> _onPurchases(List<StorePurchase> purchases) async {
    for (final p in purchases) {
      final plan = SubscriptionPlan.fromProductId(p.productId);
      if (plan == null) continue;
      switch (p.status) {
        case StorePurchaseStatus.pending:
          // Waiting on the payment method (e.g. a bank approval). The store
          // delivers it again once it clears.
          state = state.copyWith(purchasing: plan);
          _notify('Payment pending. Your plan starts once it clears.');
        case StorePurchaseStatus.canceled:
          state = state.copyWith(clearPurchasing: true);
          await _completeQuietly(p);
        case StorePurchaseStatus.error:
          state = state.copyWith(clearPurchasing: true);
          await _completeQuietly(p);
          _notify(
            p.errorMessage ?? 'The purchase did not go through.',
            isError: true,
          );
        case StorePurchaseStatus.purchased:
        case StorePurchaseStatus.restored:
          await _verify(p, plan);
      }
    }
  }

  Future<void> _verify(StorePurchase p, SubscriptionPlan plan) async {
    final restored = p.status == StorePurchaseStatus.restored;
    if (restored) _restoredSomething = true;
    final result = await _backend.verify(p);
    await result.when(
      success: (_) async {
        await _completeQuietly(p);
        _notify(
          restored
              ? 'Subscription restored.'
              : "You're on ${plan.title}. Thank you!",
        );
      },
      failure: (f) async {
        // Tell the store it was handled only when retrying cannot help;
        // otherwise leave it, so the store delivers it again next launch.
        if (f is SubscriptionFailure && f.isFinal) await _completeQuietly(p);
        _notify(f.userMessage, isError: true);
      },
    );
    state = state.copyWith(clearPurchasing: true);
  }

  Future<void> _completeQuietly(StorePurchase p) async {
    try {
      await _store.complete(p);
    } catch (e) {
      debugPrint('completePurchase failed: $e');
    }
  }

  void _notify(String message, {bool isError = false}) {
    state = state.copyWith(
      notice: SubscriptionNotice(message, isError: isError),
    );
  }
}

final subscriptionControllerProvider =
    NotifierProvider<SubscriptionController, SubscriptionUiState>(
      SubscriptionController.new,
    );
