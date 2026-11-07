import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:income_expense_tracker/core/constants/app_constants.dart';
import 'package:income_expense_tracker/data/repositories/profile_repository.dart';
import 'package:income_expense_tracker/data/repositories/subscription_repository.dart';
import 'package:income_expense_tracker/data/repositories/transaction_repository.dart';
import 'package:income_expense_tracker/data/subscriptions/subscription_store.dart';
import 'package:income_expense_tracker/models/daily_usage.dart';
import 'package:income_expense_tracker/models/subscription_plan.dart';
import 'package:income_expense_tracker/providers/auth_provider.dart';
import 'package:income_expense_tracker/providers/profile_provider.dart';
import 'package:income_expense_tracker/providers/settings_provider.dart';
import 'package:income_expense_tracker/providers/subscription_provider.dart';
import 'package:income_expense_tracker/providers/sync_provider.dart';
import 'package:income_expense_tracker/providers/transaction_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_subscriptions.dart';

const uid = 'user-1';

void main() {
  late FakeFirebaseFirestore firestore;
  late FakeSubscriptionStore store;
  late FakeSubscriptionBackend backend;
  late ProviderContainer container;

  setUp(() async {
    firestore = FakeFirebaseFirestore();
    await firestore.doc(FirestorePaths.user(uid)).set({'email': 'a@b.c'});
    store = FakeSubscriptionStore();
    backend = FakeSubscriptionBackend(
      firestore: firestore,
      currentUid: () => uid,
    );
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        currentUidProvider.overrideWithValue(uid),
        profileRepositoryProvider.overrideWithValue(
          ProfileRepository(firestore: firestore),
        ),
        transactionRepositoryProvider.overrideWithValue(
          TransactionRepository(firestore: firestore),
        ),
        subscriptionStoreProvider.overrideWithValue(store),
        subscriptionRepositoryProvider.overrideWithValue(backend),
      ],
    );
    addTearDown(container.dispose);
    // Keep the profile stream alive, as a screen watching it would.
    container.listen(userProfileProvider, (_, _) {});
  });

  /// Lets streams, microtasks and the fake Firestore catch up.
  Future<void> settle() async {
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  Future<void> setUsage({int income = 0, int expense = 0}) => firestore
      .doc(FirestorePaths.usageDay(uid, todayKey()))
      .set({'income': income, 'expense': expense, 'lastTxId': 'x'});

  group('daily limit check', () {
    Future<DailyLimitReached?> check(TransactionType type) =>
        container.read(dailyLimitCheckerProvider).check(type);

    test('a free user can add 14 a day, income and expense together', () async {
      await setUsage(income: 6, expense: 7);
      expect(await check(TransactionType.expense), isNull);
      await setUsage(income: 6, expense: 8);
      final blocked = await check(TransactionType.income);
      expect(blocked, isNotNull);
      expect(blocked!.plan, SubscriptionPlan.free);
      expect(blocked.limit, 14);
    });

    test('all 14 may be of one type', () async {
      await setUsage(expense: 13);
      expect(await check(TransactionType.expense), isNull);
      await setUsage(expense: 14);
      expect(await check(TransactionType.expense), isNotNull);
    });

    test('entries not uploaded yet count too', () async {
      await setUsage(income: 6, expense: 6);
      final local = container.read(dailyUsageStoreProvider);
      await local.recordCreated(uid, todayKey(), TransactionType.income);
      await local.recordCreated(uid, todayKey(), TransactionType.income);
      expect(await check(TransactionType.income), isNotNull);
    });

    test('a paid plan raises the limit', () async {
      await backend.grant(uid, SubscriptionPlan.basic);
      await setUsage(income: 14);
      await settle();
      expect(await check(TransactionType.income), isNull);
      await setUsage(income: 30, expense: 30);
      final blocked = await check(TransactionType.income);
      expect(blocked?.plan, SubscriptionPlan.basic);
      expect(blocked?.limit, 60);
    });

    test('an expired plan is back on the free limit', () async {
      await backend.grant(
        uid,
        SubscriptionPlan.premium,
        validFor: const Duration(days: -1),
      );
      await setUsage(expense: 14);
      await settle();
      expect(
        (await check(TransactionType.expense))?.plan,
        SubscriptionPlan.free,
      );
    });

    test("today's usage adds the server count and the device's", () async {
      container.listen(todayUsageProvider, (_, _) {});
      await setUsage(income: 2, expense: 1);
      await container
          .read(dailyUsageStoreProvider)
          .recordCreated(uid, todayKey(), TransactionType.expense);
      await settle();
      expect(
        container.read(todayUsageProvider),
        DailyUsage(day: todayKey(), income: 2, expense: 2),
      );
    });
  });

  group('buying', () {
    Future<SubscriptionController> start() async {
      container.listen(subscriptionControllerProvider, (_, _) {});
      await settle();
      return container.read(subscriptionControllerProvider.notifier);
    }

    test('loads the store prices for all three plans', () async {
      await start();
      final ui = container.read(subscriptionControllerProvider);
      expect(ui.storeAvailable, isTrue);
      expect(ui.priceFor(SubscriptionPlan.standard), '\$2.00');
    });

    test('a purchase is verified, then confirmed to the store', () async {
      final controller = await start();
      await controller.buy(SubscriptionPlan.standard);
      await settle();

      expect(store.bought, ['accounts_note_standard_monthly']);
      expect(backend.verified, hasLength(1));
      expect(
        store.completed,
        hasLength(1),
        reason: 'acknowledged only after the backend verified it',
      );
      expect(container.read(currentPlanProvider), SubscriptionPlan.standard);
      expect(container.read(subscriptionControllerProvider).purchasing, isNull);
    });

    test('upgrading hands the store the plan being replaced', () async {
      final controller = await start();
      await controller.buy(SubscriptionPlan.basic);
      await settle();
      await controller.buy(SubscriptionPlan.premium);
      await settle();

      expect(store.replaced.first, isNull);
      expect(store.replaced.last?.productId, 'accounts_note_basic_monthly');
      expect(container.read(currentPlanProvider), SubscriptionPlan.premium);
    });

    test('the yearly toggle buys the yearly product', () async {
      final controller = await start();
      controller.selectPeriod(BillingPeriod.yearly);
      expect(
        container
            .read(subscriptionControllerProvider)
            .priceFor(SubscriptionPlan.standard),
        '\$23.00',
      );
      expect(
        container
            .read(subscriptionControllerProvider)
            .yearlySavingFor(SubscriptionPlan.standard),
        '\$1.00',
        reason: 'worked out from the store prices: 12 × \$2 − \$23',
      );
      await controller.buy(SubscriptionPlan.standard);
      await settle();

      expect(store.bought, ['accounts_note_standard_yearly']);
      expect(container.read(currentPlanProvider), SubscriptionPlan.standard);
    });

    test(
      'monthly to yearly on the same plan replaces it as an upgrade',
      () async {
        final controller = await start();
        await controller.buy(SubscriptionPlan.basic);
        await settle();
        controller.selectPeriod(BillingPeriod.yearly);
        await controller.buy(SubscriptionPlan.basic);
        await settle();

        expect(store.bought.last, 'accounts_note_basic_yearly');
        expect(store.replaced.last?.productId, 'accounts_note_basic_monthly');
        expect(store.upgrades.last, isTrue);
      },
    );

    test('a yearly subscriber sees the yearly prices first', () async {
      await backend.grant(uid, SubscriptionPlan.premium);
      await firestore.doc(FirestorePaths.user(uid)).update({
        'subscriptionProductId': 'accounts_note_premium_yearly',
      });
      await start();
      await settle();
      expect(
        container.read(subscriptionControllerProvider).period,
        BillingPeriod.yearly,
      );
    });

    test('a cancelled purchase changes nothing', () async {
      store.nextOutcome = StorePurchaseStatus.canceled;
      final controller = await start();
      await controller.buy(SubscriptionPlan.basic);
      await settle();

      expect(backend.verified, isEmpty);
      expect(container.read(currentPlanProvider), SubscriptionPlan.free);
      expect(container.read(subscriptionControllerProvider).purchasing, isNull);
    });

    test('a pending payment waits without granting the plan', () async {
      store.nextOutcome = StorePurchaseStatus.pending;
      final controller = await start();
      await controller.buy(SubscriptionPlan.basic);
      await settle();

      expect(backend.verified, isEmpty);
      expect(
        container.read(subscriptionControllerProvider).purchasing,
        SubscriptionPlan.basic,
      );
      expect(
        container.read(subscriptionControllerProvider).notice?.message,
        contains('pending'),
      );
    });

    test(
      'a purchase the backend refuses for good is still acknowledged',
      () async {
        backend.rejectNext = const SubscriptionFailure(
          'This subscription is already used by another account.',
          code: 'already-exists',
          isFinal: true,
        );
        final controller = await start();
        await controller.buy(SubscriptionPlan.basic);
        await settle();

        expect(container.read(currentPlanProvider), SubscriptionPlan.free);
        expect(store.completed, hasLength(1));
        final notice = container.read(subscriptionControllerProvider).notice;
        expect(notice?.isError, isTrue);
        expect(notice?.message, contains('another account'));
      },
    );

    test(
      'a purchase that fails to verify for now is left for a retry',
      () async {
        backend.rejectNext = const SubscriptionFailure(
          'Could not reach the server.',
          code: 'unavailable',
        );
        final controller = await start();
        await controller.buy(SubscriptionPlan.basic);
        await settle();

        expect(
          store.completed,
          isEmpty,
          reason: 'the store re-delivers it on the next launch',
        );
      },
    );

    test('restore re-verifies what the store holds', () async {
      store.own(SubscriptionPlan.premium);
      final controller = await start();
      await controller.restore();
      await settle();

      expect(store.restoreCalls, 1);
      expect(backend.refreshCalls, 1);
      expect(container.read(currentPlanProvider), SubscriptionPlan.premium);
      expect(
        container.read(subscriptionControllerProvider).notice?.message,
        'Subscription restored.',
      );
    });

    test('a purchase left unconfirmed is picked up at launch', () async {
      store.own(SubscriptionPlan.standard, acknowledged: false);
      await start();
      await settle();

      expect(backend.verified, hasLength(1));
      expect(
        store.completed,
        hasLength(1),
        reason: 'Google Play refunds it if never acknowledged',
      );
      expect(container.read(currentPlanProvider), SubscriptionPlan.standard);
    });

    test('an already confirmed subscription is left alone at launch', () async {
      store.own(SubscriptionPlan.standard);
      await start();
      await settle();
      expect(backend.verified, isEmpty);
    });

    test('restore with nothing to restore says so', () async {
      final controller = await start();
      await controller.restore();
      await settle();

      expect(
        container.read(subscriptionControllerProvider).notice?.message,
        'No active subscription was found for this account.',
      );
    });

    test('a lapsed plan is re-checked with the backend once', () async {
      await backend.grant(
        uid,
        SubscriptionPlan.basic,
        validFor: const Duration(hours: -1),
      );
      await settle();
      await start();
      await settle();
      expect(backend.refreshCalls, 1);
    });

    test('without a store, buying explains why nothing happens', () async {
      store.available = false;
      final controller = await start();
      await controller.buy(SubscriptionPlan.basic);

      expect(store.bought, isEmpty);
      expect(
        container.read(subscriptionControllerProvider).notice?.message,
        'Purchases are not available on this device.',
      );
    });
  });
}
