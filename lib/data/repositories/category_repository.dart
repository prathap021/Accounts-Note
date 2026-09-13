import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/constants/app_constants.dart';
import '../../core/utils/result.dart';
import '../../models/category_model.dart';

class CategoryRepository {
  final FirebaseFirestore _firestore;
  CategoryRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _col(String uid) =>
      _firestore.collection(FirestorePaths.categories(uid));

  Stream<List<CategoryModel>> watchCategories(String uid, {TransactionType? type}) {
    Query<Map<String, dynamic>> query = _col(uid).where('isArchived', isEqualTo: false);
    if (type != null) {
      query = query.where('type', isEqualTo: type.name);
    }
    return query.snapshots().map(
          (snap) => snap.docs.map(CategoryModel.fromDoc).toList()
            ..sort((a, b) => a.name.compareTo(b.name)),
        );
  }

  Future<Result<CategoryModel>> addCategory(String uid, CategoryModel category) async {
    try {
      final ref = _col(uid).doc();
      await ref.set(category.toMap());
      return Result.success(
        CategoryModel(
          id: ref.id,
          name: category.name,
          icon: category.icon,
          color: category.color,
          type: category.type,
          createdAt: category.createdAt,
        ),
      );
    } catch (e) {
      return Result.failure(AppFailure.fromException(e));
    }
  }

  Future<Result<void>> updateCategory(String uid, CategoryModel category) async {
    try {
      await _col(uid).doc(category.id).update(category.toMap());
      return Result.success(null);
    } catch (e) {
      return Result.failure(AppFailure.fromException(e));
    }
  }

  /// Default categories are archived (hidden) rather than hard-deleted,
  /// since historical transactions reference them by denormalized name.
  /// Custom categories with no transaction history are deleted outright.
  Future<Result<void>> deleteOrArchiveCategory(
    String uid,
    CategoryModel category, {
    required bool hasTransactions,
  }) async {
    try {
      if (category.isDefault || hasTransactions) {
        await _col(uid).doc(category.id).update({'isArchived': true});
      } else {
        await _col(uid).doc(category.id).delete();
      }
      return Result.success(null);
    } catch (e) {
      return Result.failure(AppFailure.fromException(e));
    }
  }
}
