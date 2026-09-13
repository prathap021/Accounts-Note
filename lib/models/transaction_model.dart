import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';
import '../core/constants/app_constants.dart';

class TransactionModel extends Equatable {
  final String id;
  final TransactionType type;
  final double amount;
  final String categoryId;
  final String categoryName; // denormalized for fast list rendering
  final String? note;
  final DateTime date;
  final String? paymentMethod;
  final bool isRecurring;
  final String? recurringId; // link back to the recurring template, if any
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool pendingSync; // true while queued offline, for UI indicator

  const TransactionModel({
    required this.id,
    required this.type,
    required this.amount,
    required this.categoryId,
    required this.categoryName,
    this.note,
    required this.date,
    this.paymentMethod,
    this.isRecurring = false,
    this.recurringId,
    required this.createdAt,
    required this.updatedAt,
    this.pendingSync = false,
  });

  TransactionModel copyWith({
    String? id,
    TransactionType? type,
    double? amount,
    String? categoryId,
    String? categoryName,
    String? note,
    DateTime? date,
    String? paymentMethod,
    bool? isRecurring,
    String? recurringId,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? pendingSync,
  }) {
    return TransactionModel(
      id: id ?? this.id,
      type: type ?? this.type,
      amount: amount ?? this.amount,
      categoryId: categoryId ?? this.categoryId,
      categoryName: categoryName ?? this.categoryName,
      note: note ?? this.note,
      date: date ?? this.date,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      isRecurring: isRecurring ?? this.isRecurring,
      recurringId: recurringId ?? this.recurringId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      pendingSync: pendingSync ?? this.pendingSync,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'type': type.name,
      'amount': amount,
      'categoryId': categoryId,
      'categoryName': categoryName,
      'note': note,
      'date': Timestamp.fromDate(date),
      'paymentMethod': paymentMethod,
      'isRecurring': isRecurring,
      'recurringId': recurringId,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  factory TransactionModel.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return TransactionModel(
      id: doc.id,
      type: TransactionType.values.firstWhere(
        (t) => t.name == data['type'],
        orElse: () => TransactionType.expense,
      ),
      amount: (data['amount'] as num).toDouble(),
      categoryId: data['categoryId'] as String? ?? '',
      categoryName: data['categoryName'] as String? ?? 'Other',
      note: data['note'] as String?,
      date: (data['date'] as Timestamp).toDate(),
      paymentMethod: data['paymentMethod'] as String?,
      isRecurring: data['isRecurring'] as bool? ?? false,
      recurringId: data['recurringId'] as String?,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      pendingSync: doc.metadata.hasPendingWrites,
    );
  }

  @override
  List<Object?> get props => [
        id,
        type,
        amount,
        categoryId,
        categoryName,
        note,
        date,
        paymentMethod,
        isRecurring,
        recurringId,
        createdAt,
        updatedAt,
      ];
}
