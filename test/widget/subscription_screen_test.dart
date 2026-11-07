import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:income_expense_tracker/core/constants/app_constants.dart';
import 'package:income_expense_tracker/core/theme/app_theme.dart';
import 'package:income_expense_tracker/data/repositories/profile_repository.dart';
import 'package:income_expense_tracker/data/repositories/transaction_repository.dart';
import 'package:income_expense_tracker/features/subscription/limit_reached_sheet.dart';
import 'package:income_expense_tracker/features/subscription/subscription_screen.dart';
import 'package:income_expense_tracker/models/daily_usage.dart';
import 'package:income_expense_tracker/models/subscription_plan.dart';
import 'package:income_expense_tracker/providers/auth_provider.dart';
import 'package:income_expense_tracker/providers/profile_provider.dart';
import 'package:income_expense_tracker/providers/settings_provider.dart';
import 'package:income_expense_tracker/providers/subscription_provider.dart';
import 'package:income_expense_tracker/providers/transaction_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_subscriptions.dart';

const uid = 'user-1';

void main() {
  late FakeFirebaseFirestore firestore;
  late FakeSubscriptionStore store;
  late FakeSubscriptionBackend backend;
  late SharedPreferences prefs;

  setUp(() async {
    firestore = FakeFirebaseFirestore();
    await firestore.doc(FirestorePaths.user(uid)).set({'email': 'a@b.c'});
    store = FakeSubscriptionStore();
    backend = FakeSubscriptionBackend(
      firestore: firestore,
      currentUid: () => uid,
    );
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(430, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, _) => const SubscriptionScreen()),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          deviceCountryProvider.overrideWithValue('US'),
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
        child: MaterialApp.router(
          theme: AppTheme.light(),
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder inPlan(SubscriptionPlan plan, Finder finder) => find.descendant(
    of: find.byKey(Key('plan-${plan.name}')),
    matching: finder,
  );

  testWidgets('lists the three monthly plans with their prices and limits', (
    tester,
  ) async {
    await pumpScreen(tester);

    for (final (plan, price, limit) in [
      (SubscriptionPlan.basic, '\$1.00', '1,800'),
      (SubscriptionPlan.standard, '\$2.00', '3,600'),
      (SubscriptionPlan.premium, '\$3.00', '6,000'),
    ]) {
      expect(inPlan(plan, find.text(plan.title)), findsOneWidget);
      expect(inPlan(plan, find.text(price)), findsOneWidget);
      expect(
        inPlan(plan, find.text('$limit transactions a month')),
        findsOneWidget,
      );
      expect(
        inPlan(plan, find.text('Income or expense, in any mix')),
        findsOneWidget,
      );
      expect(inPlan(plan, find.text('Subscribe')), findsOneWidget);
    }
    expect(find.text('Restore purchases'), findsOneWidget);
  });

  testWidgets("shows the free plan and today's use of the shared allowance", (
    tester,
  ) async {
    await firestore.doc(FirestorePaths.usageDay(uid, todayKey())).set({
      'income': 3,
      'expense': 7,
      'lastTxId': 'x',
    });
    await pumpScreen(tester);

    expect(find.text('Free'), findsOneWidget);
    expect(find.text('No subscription'), findsOneWidget);
    expect(find.text('10 of 14'), findsOneWidget);
    expect(find.text('3 income · 7 expense'), findsOneWidget);
  });

  testWidgets('subscribing switches the screen to the new plan', (
    tester,
  ) async {
    await pumpScreen(tester);

    await tester.tap(inPlan(SubscriptionPlan.standard, find.text('Subscribe')));
    await tester.pumpAndSettle();

    expect(backend.verified, hasLength(1));
    expect(find.textContaining('Renews on'), findsOneWidget);
    expect(
      inPlan(SubscriptionPlan.standard, find.text('Current plan')),
      findsOneWidget,
    );
    expect(
      inPlan(SubscriptionPlan.premium, find.text('Upgrade')),
      findsOneWidget,
    );
    expect(
      inPlan(SubscriptionPlan.basic, find.text('Switch to Basic')),
      findsOneWidget,
    );
    expect(find.text('0 of 120'), findsOneWidget);
    expect(find.text("You're on Standard. Thank you!"), findsOneWidget);
    expect(find.text('Manage or cancel'), findsOneWidget);
  });

  testWidgets('the yearly toggle shows yearly prices and the saving', (
    tester,
  ) async {
    await pumpScreen(tester);
    await tester.tap(find.textContaining('Yearly · save'));
    await tester.pumpAndSettle();

    for (final (plan, price) in [
      (SubscriptionPlan.basic, '\$11.00'),
      (SubscriptionPlan.standard, '\$23.00'),
      (SubscriptionPlan.premium, '\$35.00'),
    ]) {
      expect(inPlan(plan, find.text(price)), findsOneWidget);
      expect(inPlan(plan, find.text(' / year')), findsOneWidget);
      expect(inPlan(plan, find.text('Save \$1.00 a year')), findsOneWidget);
    }

    await tester.tap(inPlan(SubscriptionPlan.basic, find.text('Subscribe')));
    await tester.pumpAndSettle();
    expect(store.bought, ['accounts_note_basic_yearly']);
    expect(
      inPlan(SubscriptionPlan.basic, find.text('Current plan')),
      findsOneWidget,
    );

    // The same plan, monthly, is now a switch rather than a new purchase.
    await tester.tap(find.text('Monthly'));
    await tester.pumpAndSettle();
    expect(
      inPlan(SubscriptionPlan.basic, find.text('Switch to monthly')),
      findsOneWidget,
    );
  });

  testWidgets('a cancelled plan shows when access ends', (tester) async {
    await backend.grant(
      uid,
      SubscriptionPlan.premium,
      status: 'canceled',
      autoRenewing: false,
    );
    await pumpScreen(tester);

    expect(find.textContaining('Cancelled · Premium until'), findsOneWidget);
    expect(
      inPlan(SubscriptionPlan.premium, find.text('Current plan')),
      findsOneWidget,
    );
  });

  testWidgets('says so when the device has no store', (tester) async {
    store.available = false;
    await pumpScreen(tester);

    expect(
      find.textContaining('Purchases are not available on this device'),
      findsOneWidget,
    );
    // List prices still shown, so the plans can be compared.
    expect(inPlan(SubscriptionPlan.basic, find.text('\$1')), findsOneWidget);
  });

  testWidgets('an INR user sees rupee list prices until the store answers', (
    tester,
  ) async {
    store.available = false;
    await prefs.setString('app_currency', 'INR');
    await pumpScreen(tester);

    expect(inPlan(SubscriptionPlan.basic, find.text('₹99')), findsOneWidget);
    expect(
      inPlan(SubscriptionPlan.standard, find.text('₹199')),
      findsOneWidget,
    );
    expect(inPlan(SubscriptionPlan.premium, find.text('₹299')), findsOneWidget);
  });

  testWidgets('restore reports what it found', (tester) async {
    store.own(SubscriptionPlan.basic);
    await pumpScreen(tester);

    await tester.tap(find.text('Restore purchases'));
    await tester.pumpAndSettle();

    expect(find.text('Subscription restored.'), findsOneWidget);
    expect(
      inPlan(SubscriptionPlan.basic, find.text('Current plan')),
      findsOneWidget,
    );
  });

  group('limit reached sheet', () {
    Future<void> pumpSheet(
      WidgetTester tester,
      DailyLimitReached reached,
    ) async {
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, _) => Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showDailyLimitReachedSheet(context, reached),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
          GoRoute(
            path: '/subscription',
            builder: (_, _) => const Scaffold(body: Text('PLANS')),
          ),
        ],
      );
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('explains the limit and offers the plans', (tester) async {
      await pumpSheet(
        tester,
        DailyLimitReached(
          type: TransactionType.expense,
          plan: SubscriptionPlan.free,
          limit: 14,
        ),
      );

      expect(find.text('Daily limit reached'), findsOneWidget);
      expect(
        find.textContaining(
          "You've added 14 of 14 entries today (income and expense "
          'together) on the Free plan. Upgrade for up to 200 a day',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('See plans'));
      await tester.pumpAndSettle();
      expect(find.text('PLANS'), findsOneWidget);
    });

    testWidgets('on the top plan there is nothing to upgrade to', (
      tester,
    ) async {
      await pumpSheet(
        tester,
        DailyLimitReached(
          type: TransactionType.income,
          plan: SubscriptionPlan.premium,
          limit: 200,
        ),
      );

      expect(find.text('Daily limit reached'), findsOneWidget);
      expect(find.text('See plans'), findsNothing);
      expect(find.textContaining('You can add more tomorrow'), findsOneWidget);
    });
  });
}
