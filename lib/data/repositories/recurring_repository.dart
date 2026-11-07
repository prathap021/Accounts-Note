import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../core/utils/result.dart';
import '../../models/recurring_rule.dart';

/// Recurring rules, `users/{uid}/recurringTransactions/{id}`. Firestore's
/// offline cache keeps them available with no network.
class RecurringRepository {
  RecurringRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _col(String uid) =>
      _firestore.collection(FirestorePaths.recurring(uid));

  Stream<List<RecurringRule>> watch(String uid) => _col(uid).snapshots().map(
    (s) =>
        s.docs.map(RecurringRule.fromDoc).toList()
          ..sort((a, b) => a.startDate.compareTo(b.startDate)),
  );

  Future<List<RecurringRule>> fetchActive(String uid) async {
    final snap = await _col(uid).where('active', isEqualTo: true).get();
    return snap.docs.map(RecurringRule.fromDoc).toList();
  }

  /// A new rule's id, so the first entry can be linked to it.
  String newId(String uid) => _col(uid).doc().id;

  Future<Result<void>> save(String uid, RecurringRule rule) async {
    try {
      await _col(uid).doc(rule.id).set(rule.toMap());
      return Result.success(null);
    } catch (e) {
      return Result.failure(AppFailure.fromException(e));
    }
  }

  Future<Result<void>> delete(String uid, String id) async {
    try {
      await _col(uid).doc(id).delete();
      return Result.success(null);
    } catch (e) {
      return Result.failure(AppFailure.fromException(e));
    }
  }
}

final recurringRepositoryProvider = Provider<RecurringRepository>((ref) {
  return RecurringRepository();
});
