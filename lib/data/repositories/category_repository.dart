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

  /// The name every type's catch-all category has. Transactions from a
  /// deleted category move here, so it can never be deleted itself.
  static const fallbackName = 'Other';

  /// The "Other" category of [type], created if the user has none.
  Future<Result<CategoryModel>> findOrCreateFallback(
    String uid,
    TransactionType type,
  ) async {
    try {
      final snap = await _col(uid)
          .where('type', isEqualTo: type.name)
          .where('name', isEqualTo: fallbackName)
          .limit(1)
          .get();
      if (snap.docs.isNotEmpty) {
        final doc = snap.docs.first;
        if (doc.data()['isArchived'] == true) {
          await doc.reference.update({'isArchived': false});
        }
        return Result.success(CategoryModel.fromDoc(doc));
      }
      return addCategory(
        uid,
        CategoryModel(
          id: '',
          name: fallbackName,
          icon: 'category',
          color: 0xFF757575,
          type: type,
          isDefault: true,
          createdAt: DateTime.now(),
        ),
      );
    } catch (e) {
      return Result.failure(AppFailure.fromException(e));
    }
  }

  Future<Result<void>> deleteCategory(String uid, String categoryId) async {
    try {
      await _col(uid).doc(categoryId).delete();
      return Result.success(null);
    } catch (e) {
      return Result.failure(AppFailure.fromException(e));
    }
  }
}
