import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/constants/app_constants.dart';

/// Writes the default income and expense categories for [uid]: on first
/// sign-in, and again after "Clear all data".
Future<void> seedDefaultCategories(FirebaseFirestore firestore, String uid) {
  final batch = firestore.batch();
  final col = firestore.collection(FirestorePaths.categories(uid));
  void add(Map<String, dynamic> c, TransactionType type) {
    batch.set(col.doc(), {
      'name': c['name'],
      'icon': c['icon'],
      'color': c['color'],
      'type': type.name,
      'isDefault': true,
      'isArchived': false,
      'createdAt': Timestamp.now(),
    });
  }

  for (final c in kDefaultExpenseCategories) {
    add(c, TransactionType.expense);
  }
  for (final c in kDefaultIncomeCategories) {
    add(c, TransactionType.income);
  }
  return batch.commit();
}
