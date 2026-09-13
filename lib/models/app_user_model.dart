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

  const AppUserModel({
    required this.uid,
    this.email,
    this.displayName,
    this.photoUrl,
    this.currency = 'INR',
    this.themeMode = 'system',
    this.financialMonthStartDay = 1,
    required this.createdAt,
  });

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
    );
  }

  @override
  List<Object?> get props => [uid, email, displayName, currency, themeMode];
}
