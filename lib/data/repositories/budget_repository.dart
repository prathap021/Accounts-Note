import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/constants/app_constants.dart';
import '../../core/utils/result.dart';
import '../../models/budget_model.dart';

class BudgetRepository {
  final FirebaseFirestore _firestore;
  BudgetRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _col(String uid) =>
      _firestore.collection(FirestorePaths.budgets(uid));

  Stream<List<BudgetModel>> watchBudgets(String uid, String period) {
    return _col(uid)
        .where('period', isEqualTo: period)
        .snapshots()
        .map((snap) => snap.docs.map(BudgetModel.fromDoc).toList());
  }

  Future<Result<void>> setBudget(String uid, BudgetModel budget) async {
    try {
      // One budget per (period, categoryId) — use a deterministic doc id
      // so re-saving updates instead of duplicating.
      final docId = '${budget.period}_${budget.categoryId ?? 'overall'}';
      await _col(uid).doc(docId).set(budget.toMap());
      return Result.success(null);
    } catch (e) {
      return Result.failure(AppFailure.fromException(e));
    }
  }

  Future<Result<void>> deleteBudget(String uid, String budgetId) async {
    try {
      await _col(uid).doc(budgetId).delete();
      return Result.success(null);
    } catch (e) {
      return Result.failure(AppFailure.fromException(e));
    }
  }
}
