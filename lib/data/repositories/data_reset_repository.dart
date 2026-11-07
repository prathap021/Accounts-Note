import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../core/utils/result.dart';
import 'default_categories.dart';

/// "Clear all data": every transaction, category, card and budget goes, from
/// the cloud and the device, and the default categories come back. The
/// account itself, its subscription and its settings stay; so do the daily
/// entry counters, which the rules never let the app delete (clearing must
/// not hand back today's allowance).
class DataResetRepository {
  DataResetRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  static const _collections = [
    FirestoreCollections.transactions,
    FirestoreCollections.categories,
    FirestoreCollections.creditCards,
    FirestoreCollections.budgets,
    FirestoreCollections.recurringTransactions,
    FirestoreCollections.accounts,
    FirestoreCollections.transfers,
    'receipts',
  ];

  Future<Result<void>> clearCloud(String uid) async {
    try {
      final user = _firestore.collection(FirestoreCollections.users).doc(uid);
      for (final name in _collections) {
        // Batches hold up to 500 writes; delete in pages of 400.
        while (true) {
          final page = await user.collection(name).limit(400).get();
          if (page.docs.isEmpty) break;
          final batch = _firestore.batch();
          for (final d in page.docs) {
            batch.delete(d.reference);
          }
          await batch.commit();
        }
      }
      await seedDefaultCategories(_firestore, uid);
      return Result.success(null);
    } catch (e) {
      return Result.failure(
        const AppFailure(
          'Could not clear your data. Check your connection and try again.',
          code: 'clear-failed',
        ),
      );
    }
  }
}

final dataResetRepositoryProvider = Provider<DataResetRepository>((ref) {
  return DataResetRepository();
});
