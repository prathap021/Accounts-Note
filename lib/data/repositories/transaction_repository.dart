import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/constants/app_constants.dart';
import '../../core/utils/result.dart';
import '../../models/app_user_model.dart';
import '../../models/transaction_model.dart';

class TransactionFilter {
  final DateTime? startDate;
  final DateTime? endDate;
  final TransactionType? type;
  final String? categoryId;
  final String? paymentMethod;
  final String? searchQuery;

  const TransactionFilter({
    this.startDate,
    this.endDate,
    this.type,
    this.categoryId,
    this.paymentMethod,
    this.searchQuery,
  });

  bool get isEmpty =>
      startDate == null &&
      endDate == null &&
      type == null &&
      categoryId == null &&
      paymentMethod == null &&
      (searchQuery == null || searchQuery!.isEmpty);
}

/// All reads/writes for a signed-in user's transactions live here.
class TransactionRepository {
  final FirebaseFirestore _firestore;
  TransactionRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _col(String uid) =>
      _firestore.collection(FirestorePaths.transactions(uid));

  DocumentReference<Map<String, dynamic>> _userRef(String uid) =>
      _firestore.collection(FirestoreCollections.users).doc(uid);

  static String todayKey([DateTime? now]) {
    final n = now ?? DateTime.now();
    final m = n.month.toString().padLeft(2, '0');
    final d = n.day.toString().padLeft(2, '0');
    return '${n.year}-$m-$d';
  }

  Stream<List<TransactionModel>> watchTransactions(
    String uid, {
    TransactionFilter filter = const TransactionFilter(),
    int limit = AppDefaults.pageSize,
  }) {
    Query<Map<String, dynamic>> query =
        _col(uid).orderBy('date', descending: true);

    if (filter.startDate != null) {
      query = query.where('date',
          isGreaterThanOrEqualTo: Timestamp.fromDate(filter.startDate!));
    }
    if (filter.endDate != null) {
      query = query.where('date',
          isLessThanOrEqualTo: Timestamp.fromDate(filter.endDate!));
    }
    if (filter.type != null) {
      query = query.where('type', isEqualTo: filter.type!.name);
    }
    query = query.limit(limit * 3);

    return query.snapshots().map((snap) {
      var items = snap.docs.map(TransactionModel.fromDoc).toList();
      if (filter.categoryId != null) {
        items = items.where((t) => t.categoryId == filter.categoryId).toList();
      }
      if (filter.paymentMethod != null) {
        items =
            items.where((t) => t.paymentMethod == filter.paymentMethod).toList();
      }
      if (filter.searchQuery != null && filter.searchQuery!.isNotEmpty) {
        final q = filter.searchQuery!.toLowerCase();
        items = items.where((t) {
          return t.categoryName.toLowerCase().contains(q) ||
              (t.note?.toLowerCase().contains(q) ?? false);
        }).toList();
      }
      return items.take(limit).toList();
    });
  }

  Future<Result<List<TransactionModel>>> fetchPage({
    required String uid,
    DocumentSnapshot? startAfter,
    int pageSize = AppDefaults.pageSize,
  }) async {
    try {
      Query<Map<String, dynamic>> query =
          _col(uid).orderBy('date', descending: true).limit(pageSize);
      if (startAfter != null) {
        query = query.startAfterDocument(startAfter);
      }
      final snap = await query.get();
      return Result.success(snap.docs.map(TransactionModel.fromDoc).toList());
    } catch (e) {
      return Result.failure(AppFailure.fromException(e));
    }
  }

  /// Creates a transaction and atomically enforces the free daily limit.
  Future<Result<TransactionModel>> addTransaction(
    String uid,
    TransactionModel tx,
  ) async {
    try {
      final userRef = _userRef(uid);
      final txRef = _col(uid).doc();
      final now = DateTime.now();
      final today = todayKey(now);
      final toSave = tx.copyWith(id: txRef.id, createdAt: now, updatedAt: now);

      await _firestore.runTransaction((txn) async {
        final userSnap = await txn.get(userRef);
        if (!userSnap.exists) {
          throw StateError('User profile missing.');
        }
        final profile = AppUserModel.fromDoc(userSnap);

        if (!profile.isUnlocked) {
          final used =
              profile.dailyTxnDate == today ? profile.dailyTxnCount : 0;
          if (used >= AppDefaults.freeDailyTransactionLimit) {
            throw FirebaseException(
              plugin: 'cloud_firestore',
              code: 'daily-limit',
              message:
                  'Free plan allows ${AppDefaults.freeDailyTransactionLimit} '
                  'transactions per day. Contribute to unlock unlimited access.',
            );
          }
          txn.update(userRef, {
            'dailyTxnDate': today,
            'dailyTxnCount': used + 1,
          });
        }

        txn.set(txRef, toSave.toMap());
      });

      return Result.success(toSave);
    } on FirebaseException catch (e) {
      if (e.code == 'daily-limit') {
        return Result.failure(
          AppFailure(
            e.message ??
                'Daily free limit reached. Contribute to unlock unlimited transactions.',
            code: 'daily-limit',
          ),
        );
      }
      return Result.failure(AppFailure.fromException(e));
    } catch (e) {
      return Result.failure(AppFailure.fromException(e));
    }
  }

  Future<Result<void>> updateTransaction(
    String uid,
    TransactionModel tx,
  ) async {
    try {
      final updated = tx.copyWith(updatedAt: DateTime.now());
      await _col(uid).doc(tx.id).update(updated.toMap());
      return Result.success(null);
    } catch (e) {
      return Result.failure(AppFailure.fromException(e));
    }
  }

  Future<Result<void>> deleteTransaction(String uid, String txId) async {
    try {
      final userRef = _userRef(uid);
      final txRef = _col(uid).doc(txId);
      final today = todayKey();

      await _firestore.runTransaction((txn) async {
        final txSnap = await txn.get(txRef);
        final userSnap = await txn.get(userRef);
        if (!txSnap.exists) return;

        final createdAt =
            (txSnap.data()?['createdAt'] as Timestamp?)?.toDate();
        txn.delete(txRef);

        if (userSnap.exists && createdAt != null) {
          final profile = AppUserModel.fromDoc(userSnap);
          if (!profile.isUnlocked &&
              todayKey(createdAt) == today &&
              profile.dailyTxnDate == today &&
              profile.dailyTxnCount > 0) {
            txn.update(userRef, {
              'dailyTxnCount': profile.dailyTxnCount - 1,
            });
          }
        }
      });
      return Result.success(null);
    } catch (e) {
      return Result.failure(AppFailure.fromException(e));
    }
  }

  Future<Result<Map<TransactionType, double>>> sumByType(
    String uid, {
    required DateTime start,
    required DateTime end,
  }) async {
    try {
      final snap = await _col(uid)
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
          .where('date', isLessThanOrEqualTo: Timestamp.fromDate(end))
          .get();
      double income = 0, expense = 0;
      for (final doc in snap.docs) {
        final data = doc.data();
        final amount = (data['amount'] as num).toDouble();
        if (data['type'] == TransactionType.income.name) {
          income += amount;
        } else {
          expense += amount;
        }
      }
      return Result.success({
        TransactionType.income: income,
        TransactionType.expense: expense,
      });
    } catch (e) {
      return Result.failure(AppFailure.fromException(e));
    }
  }

  Future<Result<Map<String, double>>> categoryBreakdown(
    String uid, {
    required DateTime start,
    required DateTime end,
    TransactionType type = TransactionType.expense,
  }) async {
    try {
      final snap = await _col(uid)
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
          .where('date', isLessThanOrEqualTo: Timestamp.fromDate(end))
          .where('type', isEqualTo: type.name)
          .get();
      final Map<String, double> totals = {};
      for (final doc in snap.docs) {
        final data = doc.data();
        final name = data['categoryName'] as String? ?? 'Other';
        final amount = (data['amount'] as num).toDouble();
        totals[name] = (totals[name] ?? 0) + amount;
      }
      return Result.success(totals);
    } catch (e) {
      return Result.failure(AppFailure.fromException(e));
    }
  }
}
