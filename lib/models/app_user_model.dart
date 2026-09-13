import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';

import '../core/constants/app_constants.dart';

class AppUserModel extends Equatable {
  final String uid;
  final String? email;
  final String? displayName;
  final String? photoUrl;
  final String currency;
  final String themeMode; // 'light' | 'dark' | 'system'
  final int financialMonthStartDay;
  final DateTime createdAt;

  /// True after at least one successful Stripe contribution (user tier).
  final bool hasContributed;
  final double totalContributedUsd;
  final DateTime? lastContributionAt;
  final String? stripeCustomerId;

  /// Lifetime income+expense creates (for contribution-prompt eligibility).
  final int lifetimeTxnCount;

  /// yyyy-MM-dd — dialog was shown / declined this calendar day.
  final String? contributionPromptLastShownDate;

  /// yyyy-MM-dd — user tapped Not Now (same-day suppression).
  final String? contributionDeclinedDate;

  const AppUserModel({
    required this.uid,
    this.email,
    this.displayName,
    this.photoUrl,
    this.currency = 'INR',
    this.themeMode = 'system',
    this.financialMonthStartDay = 1,
    required this.createdAt,
    this.hasContributed = false,
    this.totalContributedUsd = 0,
    this.lastContributionAt,
    this.stripeCustomerId,
    this.lifetimeTxnCount = 0,
    this.contributionPromptLastShownDate,
    this.contributionDeclinedDate,
  });

  /// Contributor badge: has ever supported the app.
  bool get isContributor => hasContributed;

  /// Contribution is a user tier, not an income/expense transaction.
  UserAccessTier get accessTier =>
      hasContributed ? UserAccessTier.contributor : UserAccessTier.free;

  /// Reached the 7-transaction threshold for optional prompts.
  bool get isContributionPromptThresholdMet =>
      lifetimeTxnCount >= AppDefaults.contributionPromptTransactionThreshold;

  /// Last contribution was in the current calendar month.
  bool contributedInCurrentMonth([DateTime? now]) {
    final at = lastContributionAt;
    if (at == null) return false;
    final n = now ?? DateTime.now();
    return at.year == n.year && at.month == n.month;
  }

  /// Whether the optional contribution dialog may be shown now.
  ///
  /// Rules:
  /// - Eligible only after [AppDefaults.contributionPromptTransactionThreshold] txs
  /// - Not again on a day the dialog was already shown / declined
  /// - Not again during the same calendar month after a successful contribution
  bool shouldShowContributionPrompt({DateTime? now, String? todayKey}) {
    if (!isContributionPromptThresholdMet) return false;
    if (contributedInCurrentMonth(now)) return false;
    final today = todayKey ?? _formatDay(now ?? DateTime.now());
    if (contributionPromptLastShownDate == today) return false;
    if (contributionDeclinedDate == today) return false;
    return true;
  }

  static String _formatDay(DateTime n) {
    final m = n.month.toString().padLeft(2, '0');
    final d = n.day.toString().padLeft(2, '0');
    return '${n.year}-$m-$d';
  }

  Map<String, dynamic> toMap() => {
        'email': email,
        'displayName': displayName,
        'photoUrl': photoUrl,
        'currency': currency,
        'themeMode': themeMode,
        'financialMonthStartDay': financialMonthStartDay,
        'createdAt': Timestamp.fromDate(createdAt),
        'hasContributed': hasContributed,
        'totalContributedUsd': totalContributedUsd,
        'lastContributionAt': lastContributionAt == null
            ? null
            : Timestamp.fromDate(lastContributionAt!),
        'stripeCustomerId': stripeCustomerId,
        'lifetimeTxnCount': lifetimeTxnCount,
        'contributionPromptLastShownDate': contributionPromptLastShownDate,
        'contributionDeclinedDate': contributionDeclinedDate,
      };

  factory AppUserModel.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    // Back-compat: older subscription users treated as contributors.
    final legacySubscribed = data['subscriptionStatus'] == 'active';
    // Migrate older daily counters into lifetime count when missing.
    final lifetime = (data['lifetimeTxnCount'] as num?)?.toInt() ??
        (data['dailyTxnCount'] as num?)?.toInt() ??
        0;
    return AppUserModel(
      uid: doc.id,
      email: data['email'] as String?,
      displayName: data['displayName'] as String?,
      photoUrl: data['photoUrl'] as String?,
      currency: data['currency'] as String? ?? 'INR',
      themeMode: data['themeMode'] as String? ?? 'system',
      financialMonthStartDay: data['financialMonthStartDay'] as int? ?? 1,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      hasContributed:
          (data['hasContributed'] as bool?) ?? legacySubscribed,
      totalContributedUsd:
          (data['totalContributedUsd'] as num?)?.toDouble() ?? 0,
      lastContributionAt:
          (data['lastContributionAt'] as Timestamp?)?.toDate(),
      stripeCustomerId: data['stripeCustomerId'] as String?,
      lifetimeTxnCount: lifetime,
      contributionPromptLastShownDate:
          data['contributionPromptLastShownDate'] as String?,
      contributionDeclinedDate: data['contributionDeclinedDate'] as String?,
    );
  }

  AppUserModel copyWith({
    String? displayName,
    String? photoUrl,
    String? currency,
    String? themeMode,
    int? financialMonthStartDay,
    bool? hasContributed,
    double? totalContributedUsd,
    DateTime? lastContributionAt,
    String? stripeCustomerId,
    int? lifetimeTxnCount,
    String? contributionPromptLastShownDate,
    String? contributionDeclinedDate,
  }) {
    return AppUserModel(
      uid: uid,
      email: email,
      displayName: displayName ?? this.displayName,
      photoUrl: photoUrl ?? this.photoUrl,
      currency: currency ?? this.currency,
      themeMode: themeMode ?? this.themeMode,
      financialMonthStartDay:
          financialMonthStartDay ?? this.financialMonthStartDay,
      createdAt: createdAt,
      hasContributed: hasContributed ?? this.hasContributed,
      totalContributedUsd: totalContributedUsd ?? this.totalContributedUsd,
      lastContributionAt: lastContributionAt ?? this.lastContributionAt,
      stripeCustomerId: stripeCustomerId ?? this.stripeCustomerId,
      lifetimeTxnCount: lifetimeTxnCount ?? this.lifetimeTxnCount,
      contributionPromptLastShownDate: contributionPromptLastShownDate ??
          this.contributionPromptLastShownDate,
      contributionDeclinedDate:
          contributionDeclinedDate ?? this.contributionDeclinedDate,
    );
  }

  @override
  List<Object?> get props => [
        uid,
        email,
        displayName,
        currency,
        themeMode,
        hasContributed,
        totalContributedUsd,
        lastContributionAt,
        lifetimeTxnCount,
        contributionPromptLastShownDate,
        contributionDeclinedDate,
      ];
}
