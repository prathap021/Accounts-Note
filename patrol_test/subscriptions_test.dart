import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:income_expense_tracker/core/constants/app_constants.dart';
import 'package:income_expense_tracker/models/daily_usage.dart';
import 'package:income_expense_tracker/models/subscription_plan.dart';
import 'package:patrol/patrol.dart';

import 'support/steps.dart';
import 'support/test_app.dart';

extension on FakeBackend {
  /// Today's server count, as if entries had already been uploaded from this
  /// or another device.
  Future<void> seedUsage(String uid, {int income = 0, int expense = 0}) =>
      firestore.doc(FirestorePaths.usageDay(uid, todayKey())).set({
        'income': income,
        'expense': expense,
        'lastTxId': 'seeded',
      });
}

extension on PatrolIntegrationTester {
  Future<void> openPlans() async {
    await openSettings();
    final tile = this('Subscription');
    await reveal(tile, scrollIn: find.byType(Scrollable).first);
    await tile.tap();
    await this('MONTHLY PLANS').waitUntilVisible();
  }

  /// Back to the status card at the top of the plan screen. The list is
  /// lazy, so once scrolled past, the card is not built to scroll to.
  Future<void> scrollPlansToTop() async {
    await tester.fling(
      find.byType(Scrollable).first,
      const Offset(0, 3000),
      3000,
    );
    await pumpAndTrySettle();
    await this('CURRENT PLAN').waitUntilVisible();
  }

  PatrolFinder plan(SubscriptionPlan p) => this(Key('plan-${p.name}'));

  /// Scrolls the plan card into view and taps its button.
  Future<void> tapPlanButton(SubscriptionPlan p, String label) async {
    final button = plan(p).$(label);
    await reveal(button, scrollIn: find.byType(Scrollable).first);
    await button.tap();
  }

  /// Taps Add and picks [type] in the "What would you like to add?" sheet.
  Future<void> startAdding(TransactionType type) async {
    await hideKeyboard();
    await this(FloatingActionButton).$('Add').tap();
    await sheet.$(type == TransactionType.income ? 'Income' : 'Expense').tap();
  }
}

void main() {
  patrolTest('a free user gets 7 expenses a day, then is offered the plans', (
    $,
  ) async {
    await launchSignedIn(
      $,
      seed: (backend, user) => backend.seedUsage(user.uid, expense: 6),
    );

    // The 7th expense of the day still goes in.
    await $.addTransaction(
      type: TransactionType.expense,
      amount: 450,
      category: 'Food',
    );
    await $.dismissSnackBars();

    // The 8th is stopped before the form even opens.
    await $.startAdding(TransactionType.expense);
    await $('Daily expense limit reached').waitUntilVisible();
    expect(
      $(
        RegExp(
          r"You've added 7 of 7 expense entries today on the Free "
          r'plan\. Upgrade for up to 100 a day',
        ),
      ),
      findsOneWidget,
    );
    expect($('Add expense'), findsNothing);

    // Income has its own allowance.
    await $('Not now').tap();
    await $.startAdding(TransactionType.income);
    await $('Add income').waitUntilVisible();
    await $.goBack();

    // The upgrade path, from the prompt to a plan that lets it through.
    await $.startAdding(TransactionType.expense);
    await $('See plans').tap();
    await $('MONTHLY PLANS').waitUntilVisible();
    await $.tapPlanButton(SubscriptionPlan.basic, 'Subscribe');
    await $("You're on Basic. Thank you!").waitUntilVisible();
    await $.goBack();

    await $.addTransaction(
      type: TransactionType.expense,
      amount: 120,
      category: 'Transport',
    );
  });

  patrolTest(
    'the plan screen shows every plan, the current status and today\'s use',
    ($) async {
      final (backend, _) = await launchSignedIn(
        $,
        seed: (backend, user) =>
            backend.seedUsage(user.uid, income: 2, expense: 5),
      );

      await $.openPlans();
      expect($('Free'), findsOneWidget);
      expect($('No subscription'), findsOneWidget);
      expect($('2 of 7'), findsOneWidget);
      expect($('5 of 7'), findsOneWidget);

      for (final (p, price, limit) in [
        (SubscriptionPlan.basic, '₹99.00', 30),
        (SubscriptionPlan.standard, '₹199.00', 60),
        (SubscriptionPlan.premium, '₹299.00', 100),
      ]) {
        await $.reveal($.plan(p), scrollIn: find.byType(Scrollable).first);
        expect($.plan(p).$(price), findsOneWidget);
        expect($.plan(p).$('$limit income entries a day'), findsOneWidget);
        expect($.plan(p).$('$limit expense entries a day'), findsOneWidget);
      }

      await $.tapPlanButton(SubscriptionPlan.premium, 'Subscribe');
      await $("You're on Premium. Thank you!").waitUntilVisible();
      expect(backend.store.bought, ['accounts_note_premium_monthly']);
      expect(
        backend.store.completed,
        hasLength(1),
        reason: 'acknowledged to the store once verified',
      );
      await $.scrollPlansToTop();
      expect($(RegExp(r'^Renews on ')), findsOneWidget);
      expect($('2 of 100'), findsOneWidget);
      expect($('5 of 100'), findsOneWidget);

      // Settings now names the plan.
      await $.goBack();
      await $('Premium · 100 income + 100 expense a day').waitUntilVisible();
    },
  );

  patrolTest('upgrading replaces the current plan in the store', ($) async {
    final (backend, _) = await launchSignedIn(
      $,
      seed: (backend, user) async {
        await backend.subscriptions.grant(user.uid, SubscriptionPlan.basic);
        backend.store.own(SubscriptionPlan.basic);
      },
    );

    await $.openPlans();
    await $.reveal(
      $.plan(SubscriptionPlan.basic).$('Current plan'),
      scrollIn: find.byType(Scrollable).first,
    );
    await $.tapPlanButton(SubscriptionPlan.standard, 'Upgrade');
    await $("You're on Standard. Thank you!").waitUntilVisible();

    expect(
      backend.store.replaced.single?.productId,
      'accounts_note_basic_monthly',
      reason: 'Google Play switches plans in place',
    );
    await $.reveal(
      $.plan(SubscriptionPlan.standard).$('Current plan'),
      scrollIn: find.byType(Scrollable).first,
    );
  });

  patrolTest('restore brings back a subscription after a reinstall', ($) async {
    final (backend, _) = await launchSignedIn(
      $,
      seed: (backend, user) async =>
          backend.store.own(SubscriptionPlan.standard),
    );

    await $.openPlans();
    expect($('Free'), findsOneWidget);
    final restore = $('Restore purchases');
    await $.reveal(restore, scrollIn: find.byType(Scrollable).first);
    await restore.tap();

    await $('Subscription restored.').waitUntilVisible();
    expect(
      backend.subscriptions.verified.single.productId,
      'accounts_note_standard_monthly',
    );
    await $.scrollPlansToTop();
    expect($('Standard'), findsWidgets);
    expect($(RegExp(r'^Renews on ')), findsOneWidget);
  });

  patrolTest(
    'a cancelled subscription keeps its limits until the month is up',
    ($) async {
      await launchSignedIn(
        $,
        seed: (backend, user) async {
          await backend.subscriptions.grant(
            user.uid,
            SubscriptionPlan.standard,
            status: 'canceled',
            autoRenewing: false,
          );
          await backend.seedUsage(user.uid, expense: 7);
        },
      );

      // Past the free limit, but the paid month is not over.
      await $.addTransaction(
        type: TransactionType.expense,
        amount: 99,
        category: 'Food',
      );

      await $.openPlans();
      expect($(RegExp(r'^Cancelled · Standard until ')), findsOneWidget);
      expect($('8 of 60'), findsOneWidget);
    },
  );
}
