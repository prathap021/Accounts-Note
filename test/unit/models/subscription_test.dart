import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:income_expense_tracker/core/constants/app_constants.dart';
import 'package:income_expense_tracker/data/subscriptions/subscription_store.dart';
import 'package:income_expense_tracker/models/app_user_model.dart';
import 'package:income_expense_tracker/models/subscription_plan.dart';
import 'package:income_expense_tracker/models/subscription_status.dart';

void main() {
  final now = DateTime(2026, 11, 7, 12);

  group('SubscriptionPlan', () {
    test('daily limits match the published plans', () {
      final table = {
        for (final p in SubscriptionPlan.values)
          p: (p.priceLabel, p.dailyIncomeLimit, p.dailyExpenseLimit),
      };
      expect(table, {
        SubscriptionPlan.free: ('₹0', 7, 7),
        SubscriptionPlan.basic: ('₹99', 30, 30),
        SubscriptionPlan.standard: ('₹199', 60, 60),
        SubscriptionPlan.premium: ('₹299', 100, 100),
      });
    });

    test('limits are per type', () {
      expect(SubscriptionPlan.basic.limitFor(TransactionType.income), 30);
      expect(SubscriptionPlan.basic.limitFor(TransactionType.expense), 30);
    });

    test('store product ids map back to their plans', () {
      expect(SubscriptionPlan.productIds, {
        'accounts_note_basic_monthly',
        'accounts_note_standard_monthly',
        'accounts_note_premium_monthly',
      });
      for (final p in SubscriptionPlan.paid) {
        expect(SubscriptionPlan.fromProductId(p.productId), p);
      }
      expect(SubscriptionPlan.fromProductId('something_else'), isNull);
    });

    test('plans are ordered cheapest first', () {
      expect(
        SubscriptionPlan.premium.isHigherThan(SubscriptionPlan.basic),
        isTrue,
      );
      expect(
        SubscriptionPlan.basic.isHigherThan(SubscriptionPlan.standard),
        isFalse,
      );
      expect(
        SubscriptionPlan.basic.isHigherThan(SubscriptionPlan.free),
        isTrue,
      );
    });
  });

  group('SubscriptionStatus.effectivePlan', () {
    SubscriptionStatus status(SubscriptionState state, {int days = 10}) =>
        SubscriptionStatus(
          plan: SubscriptionPlan.standard,
          state: state,
          expiresAt: now.add(Duration(days: days)),
          autoRenewing: state == SubscriptionState.active,
          platform: 'android',
        );

    test('active, grace and cancelled-but-paid keep the plan', () {
      for (final s in [
        SubscriptionState.active,
        SubscriptionState.grace,
        SubscriptionState.canceled,
      ]) {
        expect(
          status(s).effectivePlan(now),
          SubscriptionPlan.standard,
          reason: s.name,
        );
      }
    });

    test('on hold, paused and expired fall back to free at once', () {
      for (final s in [
        SubscriptionState.onHold,
        SubscriptionState.paused,
        SubscriptionState.expired,
      ]) {
        expect(
          status(s).effectivePlan(now),
          SubscriptionPlan.free,
          reason: s.name,
        );
      }
    });

    test('the plan ends when the paid period does', () {
      final lapsed = status(SubscriptionState.active, days: -1);
      expect(lapsed.effectivePlan(now), SubscriptionPlan.free);
      expect(
        lapsed.needsRefresh(now),
        isTrue,
        reason: 'the store may have renewed it without telling us',
      );
      expect(status(SubscriptionState.active).needsRefresh(now), isFalse);
    });

    test('no subscription is the free plan', () {
      expect(SubscriptionStatus.none.effectivePlan(now), SubscriptionPlan.free);
      expect(SubscriptionStatus.none.needsRefresh(now), isFalse);
    });
  });

  group('reading the profile', () {
    test('subscription fields written by the backend are parsed', () {
      final s = SubscriptionStatus.fromUserData({
        'subscriptionPlan': 'premium',
        'subscriptionStatus': 'on_hold',
        'subscriptionExpiresAt': Timestamp.fromDate(now),
        'subscriptionAutoRenewing': true,
        'subscriptionPlatform': 'ios',
        'subscriptionProductId': 'accounts_note_premium_monthly',
      });
      expect(s.plan, SubscriptionPlan.premium);
      expect(s.state, SubscriptionState.onHold);
      expect(s.expiresAt, now);
      expect(s.autoRenewing, isTrue);
      expect(s.platform, 'ios');
    });

    test('old Stripe contribution fields no longer mean anything', () {
      final s = SubscriptionStatus.fromUserData({
        'hasContributed': true,
        'subscriptionStatus': 'active',
      });
      expect(s, SubscriptionStatus.none);
    });

    test('the app never writes subscription fields itself', () {
      final user = AppUserModel(
        uid: 'u',
        createdAt: now,
        subscription: SubscriptionStatus(
          plan: SubscriptionPlan.premium,
          state: SubscriptionState.active,
          expiresAt: now,
        ),
      );
      expect(
        user.toMap().keys.where((k) => k.startsWith('subscription')),
        isEmpty,
        reason: 'the security rules refuse them from the app',
      );
    });
  });

  test('the App Store account tag matches the one the backend derives', () {
    // functions/src/subscriptions.ts uuidV5("accountsnote:user-1"), and
    // Python's uuid.uuid5(NAMESPACE_URL, "accountsnote:user-1").
    expect(
      appAccountTokenFor('user-1'),
      '534f3aaa-de83-54d0-bd96-e73beb8ec316',
    );
  });
}
