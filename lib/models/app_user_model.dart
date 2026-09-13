import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';

class AppUserModel extends Equatable {
  final String uid;
  final String? email;
  final String? displayName;
  final String? photoUrl;
  final String currency;
  final String themeMode; // 'light' | 'dark' | 'system'
  final int financialMonthStartDay;
  final DateTime createdAt;

  /// One-time Stripe contribution unlocks unlimited transactions.
  final bool hasContributed;
  final double totalContributedUsd;
  final DateTime? lastContributionAt;
  final String? stripeCustomerId;

  /// Local usage counters for the free daily limit (client-maintained).
  final String? dailyTxnDate; // yyyy-MM-dd
  final int dailyTxnCount;

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
    this.dailyTxnDate,
    this.dailyTxnCount = 0,
  });

  /// Contributors (after a successful Stripe payment) have unlimited adds.
  bool get isUnlocked => hasContributed;

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
        'dailyTxnDate': dailyTxnDate,
        'dailyTxnCount': dailyTxnCount,
      };

  factory AppUserModel.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    // Back-compat: older subscription users treated as unlocked.
    final legacySubscribed = data['subscriptionStatus'] == 'active';
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
      dailyTxnDate: data['dailyTxnDate'] as String?,
      dailyTxnCount: (data['dailyTxnCount'] as num?)?.toInt() ?? 0,
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
    String? dailyTxnDate,
    int? dailyTxnCount,
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
      dailyTxnDate: dailyTxnDate ?? this.dailyTxnDate,
      dailyTxnCount: dailyTxnCount ?? this.dailyTxnCount,
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
        dailyTxnCount,
        dailyTxnDate,
      ];
}
