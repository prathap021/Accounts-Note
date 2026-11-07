import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';

import 'subscription_status.dart';

class AppUserModel extends Equatable {
  final String uid;
  final String? email;
  final String? displayName;
  final String? photoUrl;
  final String currency;
  final String themeMode; // 'light' | 'dark' | 'system'
  final int financialMonthStartDay;
  final DateTime createdAt;

  /// The subscription the backend last verified. Server-owned: the app reads
  /// it, never writes it.
  final SubscriptionStatus subscription;

  const AppUserModel({
    required this.uid,
    this.email,
    this.displayName,
    this.photoUrl,
    this.currency = 'INR',
    this.themeMode = 'system',
    this.financialMonthStartDay = 1,
    required this.createdAt,
    this.subscription = SubscriptionStatus.none,
  });

  /// The profile as the app writes it. Subscription fields are left out on
  /// purpose: only the backend may set them, and the rules refuse them.
  Map<String, dynamic> toMap() => {
        'email': email,
        'displayName': displayName,
        'photoUrl': photoUrl,
        'currency': currency,
        'themeMode': themeMode,
        'financialMonthStartDay': financialMonthStartDay,
        'createdAt': Timestamp.fromDate(createdAt),
      };

  factory AppUserModel.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return AppUserModel(
      uid: doc.id,
      email: data['email'] as String?,
      displayName: data['displayName'] as String?,
      photoUrl: data['photoUrl'] as String?,
      currency: data['currency'] as String? ?? 'INR',
      themeMode: data['themeMode'] as String? ?? 'system',
      financialMonthStartDay: data['financialMonthStartDay'] as int? ?? 1,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      subscription: SubscriptionStatus.fromUserData(data),
    );
  }

  AppUserModel copyWith({
    String? displayName,
    String? photoUrl,
    String? currency,
    String? themeMode,
    int? financialMonthStartDay,
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
      subscription: subscription,
    );
  }

  @override
  List<Object?> get props => [
        uid,
        email,
        displayName,
        photoUrl,
        currency,
        themeMode,
        subscription,
      ];
}
