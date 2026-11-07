import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';

/// A credit card the user pays with, so expenses can be marked against it and
/// totalled per card.
///
/// Only the last four digits are ever kept. The app has no use for the full
/// number, expiry or CVV, and a ledger is not a safe place to hold them.
class CreditCardModel extends Equatable {
  final String id;
  final String name; // e.g. "HDFC Millennia"
  final String? last4;
  final int color; // ARGB int
  final double? creditLimit;
  final DateTime createdAt;

  const CreditCardModel({
    required this.id,
    required this.name,
    this.last4,
    required this.color,
    this.creditLimit,
    required this.createdAt,
  });

  // The limits below mirror isValidCreditCard in firestore.rules; the form
  // checks them first so the user gets a reason rather than a refusal.

  static const maxNameLength = 50;

  /// Exclusive upper bound on [creditLimit].
  static const maxCreditLimit = 1e12;

  /// True for exactly four digits.
  static bool isValidLast4(String value) => RegExp(r'^\d{4}$').hasMatch(value);

  /// True when [text] holds a run of 12 or more digits once spaces and dashes
  /// are dropped — the shape of a full card number.
  static bool containsCardNumber(String text) =>
      RegExp(r'\d{12,}').hasMatch(text.replaceAll(RegExp(r'[ -]'), ''));

  /// The name plus the last four digits when known, which is what tells two
  /// cards from the same bank apart.
  String get displayName => last4 == null ? name : '$name ••$last4';

  CreditCardModel copyWith({
    String? id,
    String? name,
    String? last4,
    bool clearLast4 = false,
    int? color,
    double? creditLimit,
    bool clearCreditLimit = false,
  }) {
    return CreditCardModel(
      id: id ?? this.id,
      name: name ?? this.name,
      last4: clearLast4 ? null : (last4 ?? this.last4),
      color: color ?? this.color,
      creditLimit:
          clearCreditLimit ? null : (creditLimit ?? this.creditLimit),
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'last4': last4,
        'color': color,
        'creditLimit': creditLimit,
        'createdAt': Timestamp.fromDate(createdAt),
      };

  factory CreditCardModel.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return CreditCardModel(
      id: doc.id,
      name: data['name'] as String? ?? 'Credit card',
      last4: data['last4'] as String?,
      color: data['color'] as int? ?? 0xFF1E3A8A,
      creditLimit: (data['creditLimit'] as num?)?.toDouble(),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  @override
  List<Object?> get props => [id, name, last4, color, creditLimit];
}
