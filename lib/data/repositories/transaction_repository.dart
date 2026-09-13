import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/constants/app_constants.dart';
import '../../core/utils/result.dart';
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
/// Firestore's offline persistence (enabled once in main.dart) means
/// these calls work transparently offline; cloud_firestore queues writes
/// and syncs automatically when connectivity returns.
class TransactionRepository {
  final FirebaseFirestore _firestore;
  TransactionRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _col(String uid) =>
      _firestore.collection(FirestorePaths.transactions(uid));

  /// Real-time stream of transactions for a date range, most recent first.
  /// Client-side filters (category/payment/search) are applied after the
  /// snapshot arrives to avoid needing a composite index for every
  /// combination; date range + type are server-side for efficiency.
  Stream<List<TransactionModel>> watchTransactions(
    String uid, {
    TransactionFilter filter = const TransactionFilter(),
    int limit = AppDefaults.pageSize,
  }) {
    Query<Map<String, dynamic>> query = _col(uid).orderBy('date', descending: true);

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
    query = query.limit(limit * 3); // headroom for client-side filtering

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

  /// Cursor-based pagination for the full transaction history screen.
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

  Future<Result<TransactionModel>> addTransaction(
    String uid,
    TransactionModel tx,
  ) async {
    try {
      final ref = _col(uid).doc();
      final now = DateTime.now();
      final toSave = tx.copyWith(id: ref.id, createdAt: now, updatedAt: now);
      await ref.set(toSave.toMap());
      return Result.success(toSave);
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
      await _col(uid).doc(txId).delete();
      return Result.success(null);
    } catch (e) {
      return Result.failure(AppFailure.fromException(e));
    }
  }

  /// Sum of income/expense for a given closed date range — used by the
  /// dashboard and reports. Reads once (not a stream) to keep Firestore
  /// costs down; callers can refresh on pull-to-refresh or after writes.
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

  /// Category-wise expense totals for charts (pie/bar), single range read.
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
