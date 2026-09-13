import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';

/// A budget is scoped to one calendar month (yyyy-MM as `period`) and
/// optionally to a single category. A null [categoryId] means it is the
/// overall monthly budget.
class BudgetModel extends Equatable {
  final String id;
  final String period; // e.g. "2026-09"
  final String? categoryId;
  final String? categoryName;
  final double limit;
  final double alertThresholdPercent; // e.g. 80 => warn at 80% spent
  final DateTime createdAt;

  const BudgetModel({
    required this.id,
    required this.period,
    this.categoryId,
    this.categoryName,
    required this.limit,
    this.alertThresholdPercent = 80,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        'period': period,
        'categoryId': categoryId,
        'categoryName': categoryName,
        'limit': limit,
        'alertThresholdPercent': alertThresholdPercent,
        'createdAt': Timestamp.fromDate(createdAt),
      };

  factory BudgetModel.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return BudgetModel(
      id: doc.id,
      period: data['period'] as String,
      categoryId: data['categoryId'] as String?,
      categoryName: data['categoryName'] as String?,
      limit: (data['limit'] as num).toDouble(),
      alertThresholdPercent:
          (data['alertThresholdPercent'] as num?)?.toDouble() ?? 80,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  @override
  List<Object?> get props => [id, period, categoryId, limit, alertThresholdPercent];
}
