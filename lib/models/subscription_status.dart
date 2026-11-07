import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';

import 'subscription_plan.dart';

/// Where the store says a subscription stands, as written by the backend.
///
/// Mirrors what Google Play and the App Store report, folded into one set of
/// states (see `functions/src/subscriptions.ts`).
enum SubscriptionState {
  /// No subscription has ever been verified for this account.
  none,

  /// Paid and renewing.
  active,

  /// Renewal payment failed, but the store keeps access open while it
  /// retries.
  grace,

  /// Auto-renew turned off. Access continues until [SubscriptionStatus.expiresAt].
  canceled,

  /// Payment failed and the grace period ran out. No access until fixed.
  onHold,

  /// Paused by the user (Google Play). No access until it resumes.
  paused,

  /// Ended or refunded.
  expired;

  static SubscriptionState fromName(String? name) => switch (name) {
    'active' => active,
    'grace' => grace,
    'canceled' => canceled,
    'on_hold' => onHold,
    'paused' => paused,
    'expired' => expired,
    _ => none,
  };
}

/// The subscription on a user's profile (`users/{uid}`).
///
/// Only the backend writes these fields; the security rules refuse them from
/// the app. The rules read [plan] and [expiresAt] to decide the daily limit,
/// so the same "paid and not yet expired" test is applied here.
class SubscriptionStatus extends Equatable {
  final SubscriptionPlan plan;
  final SubscriptionState state;

  /// End of the paid period: the next renewal date while renewing, the last
  /// day of access once cancelled.
  final DateTime? expiresAt;
  final bool autoRenewing;

  /// `android` or `ios`: where it was bought, and so where it is managed.
  final String? platform;
  final String? productId;

  const SubscriptionStatus({
    this.plan = SubscriptionPlan.free,
    this.state = SubscriptionState.none,
    this.expiresAt,
    this.autoRenewing = false,
    this.platform,
    this.productId,
  });

  static const none = SubscriptionStatus();

  /// The plan whose limits apply right now.
  ///
  /// A cancelled subscription keeps its plan until the paid period ends; an
  /// expired, paused or on-hold one falls back to free at once.
  SubscriptionPlan effectivePlan([DateTime? now]) {
    final end = expiresAt;
    if (!plan.isPaid || end == null) return SubscriptionPlan.free;
    final entitled =
        state == SubscriptionState.active ||
        state == SubscriptionState.grace ||
        state == SubscriptionState.canceled;
    if (!entitled) return SubscriptionPlan.free;
    return end.isAfter(now ?? DateTime.now()) ? plan : SubscriptionPlan.free;
  }

  bool isActive([DateTime? now]) => effectivePlan(now).isPaid;

  /// Had a paid plan whose period has run out, so the store may have renewed
  /// it without the backend hearing yet. Worth asking the backend to check.
  bool needsRefresh([DateTime? now]) {
    final end = expiresAt;
    return plan.isPaid &&
        end != null &&
        !end.isAfter(now ?? DateTime.now()) &&
        state != SubscriptionState.expired;
  }

  factory SubscriptionStatus.fromUserData(Map<String, dynamic> data) {
    final plan = SubscriptionPlan.fromName(data['subscriptionPlan'] as String?);
    if (!plan.isPaid) return none;
    return SubscriptionStatus(
      plan: plan,
      state: SubscriptionState.fromName(data['subscriptionStatus'] as String?),
      expiresAt: (data['subscriptionExpiresAt'] as Timestamp?)?.toDate(),
      autoRenewing: data['subscriptionAutoRenewing'] as bool? ?? false,
      platform: data['subscriptionPlatform'] as String?,
      productId: data['subscriptionProductId'] as String?,
    );
  }

  @override
  List<Object?> get props => [
    plan,
    state,
    expiresAt,
    autoRenewing,
    platform,
    productId,
  ];
}
