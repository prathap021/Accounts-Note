import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/constants/app_constants.dart';
import '../../core/utils/result.dart';
import '../../models/daily_usage.dart';
import '../../models/transaction_model.dart';

class TransactionFilter {
  final DateTime? startDate;
  final DateTime? endDate;
  final TransactionType? type;
  final String? categoryId;
  final String? paymentMethod;
  final String? creditCardId;
  final String? searchQuery;

  const TransactionFilter({
    this.startDate,
    this.endDate,
    this.type,
    this.categoryId,
    this.paymentMethod,
    this.creditCardId,
    this.searchQuery,
  });

  bool get isEmpty =>
      startDate == null &&
      endDate == null &&
      type == null &&
      categoryId == null &&
      paymentMethod == null &&
      creditCardId == null &&
      (searchQuery == null || searchQuery!.isEmpty);

  /// Whether [t] passes every constraint (they combine with AND). Both date
  /// bounds are inclusive.
  ///
  /// The single definition of what a filter means, so the Activity list and
  /// the live total in the filter sheet can never disagree.
  bool matches(TransactionModel t) {
    if (startDate != null && t.date.isBefore(startDate!)) return false;
    if (endDate != null && t.date.isAfter(endDate!)) return false;
    if (type != null && t.type != type) return false;
    if (categoryId != null && t.categoryId != categoryId) return false;
    if (paymentMethod != null && t.paymentMethod != paymentMethod) return false;
    if (creditCardId != null && t.creditCardId != creditCardId) return false;

    final query = searchQuery?.trim().toLowerCase();
    if (query != null && query.isNotEmpty) {
      return t.categoryName.toLowerCase().contains(query) ||
          (t.note?.toLowerCase().contains(query) ?? false) ||
          (t.paymentMethod?.toLowerCase().contains(query) ?? false) ||
          (t.creditCardName?.toLowerCase().contains(query) ?? false);
    }
    return true;
  }
}

/// All reads/writes for a signed-in user's transactions live here.
class TransactionRepository {
  final FirebaseFirestore _firestore;
  TransactionRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _col(String uid) =>
      _firestore.collection(FirestorePaths.transactions(uid));

  Stream<List<TransactionModel>> watchTransactions(
    String uid, {
    TransactionFilter filter = const TransactionFilter(),
    int limit = AppDefaults.pageSize,
  }) {
    // Only constrain by date on the server. Equality filters on `type` plus
    // `orderBy(date)` need composite indexes that may still be building; apply
    // type/category/payment/search client-side so Activity filters stay usable.
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

    final needsClientFilter = filter.type != null ||
        filter.categoryId != null ||
        filter.paymentMethod != null ||
        filter.creditCardId != null ||
        (filter.searchQuery != null && filter.searchQuery!.isNotEmpty);
    query = query.limit(needsClientFilter ? (limit * 15).clamp(limit, 300) : limit);

    return query.snapshots().map((snap) {
      var items = snap.docs.map(TransactionModel.fromDoc).toList();
      if (filter.type != null) {
        items = items.where((t) => t.type == filter.type).toList();
      }
      if (filter.categoryId != null) {
        items = items.where((t) => t.categoryId == filter.categoryId).toList();
      }
      if (filter.paymentMethod != null) {
        items =
            items.where((t) => t.paymentMethod == filter.paymentMethod).toList();
      }
      if (filter.creditCardId != null) {
        items =
            items.where((t) => t.creditCardId == filter.creditCardId).toList();
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

  // ---- Sync-facing API -------------------------------------------------
  // These are what SyncManager drives. They throw on failure (rather than
  // returning a Result) so the manager can mark the record failed and retry.

  /// Writes the record at its own client-generated id, merging.
  ///
  /// This is what makes the queue safe to replay: pushing the same record
  /// twice updates one document instead of creating two, so a timeout or a
  /// mid-push crash cannot duplicate the user's ledger.
  Future<void> upsertTransaction(String uid, TransactionModel tx) async {
    await _col(uid).doc(tx.id).set(tx.toMap(), SetOptions(merge: true));
  }

  /// Deleting an id that is already gone is a no-op, which keeps replaying a
  /// delete safe.
  Future<void> deleteTransactionRaw(String uid, String txId) async {
    await _col(uid).doc(txId).delete();
  }

  /// Full pull used to reconcile the local store with the cloud.
  Future<Result<List<TransactionModel>>> fetchAllForSync(
    String uid, {
    int limit = 2000,
  }) async {
    try {
      final snap = await _col(uid)
          .orderBy('date', descending: true)
          .limit(limit)
          .get(const GetOptions(source: Source.server));
      return Result.success(snap.docs.map(TransactionModel.fromDoc).toList());
    } catch (e) {
      return Result.failure(AppFailure.fromException(e));
    }
  }

  /// Uploads a new entry together with the bump to its day's counter.
  ///
  /// The two go in one batch because the security rules accept a new
  /// transaction only when the same write moves
  /// `users/{uid}/usage/{day}` up by exactly one for its type, names this
  /// entry as `lastTxId`, and stays within the plan's daily limit. Anything
  /// else — a create without the bump, two creates on one bump, a counter
  /// past the limit — is refused as a whole.
  ///
  /// Replaying this after a lost acknowledgement finds the document already
  /// there, which the rules treat as an update. The counter still moves by
  /// one, so a retry can cost the user one entry of allowance but can never
  /// duplicate the transaction.
  Future<void> createTransactionCounted(String uid, TransactionModel tx) async {
    final offset = tx.usageTzOffsetMinutes;
    final toSave = tx.copyWith(createdTzOffsetMinutes: offset);
    final usageRef = _firestore.doc(FirestorePaths.usageDay(uid, tx.usageDay));
    final batch = _firestore.batch()
      ..set(_col(uid).doc(tx.id), toSave.toMap(), SetOptions(merge: true))
      ..set(
        usageRef,
        {
          tx.type.name: FieldValue.increment(1),
          'lastTxId': tx.id,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    await batch.commit();
  }

  /// The server's count for [day]: every entry uploaded for it, from any
  /// device. Emits from the local Firestore cache first, so it works offline.
  Stream<DailyUsage> watchUsage(String uid, String day) {
    return _firestore
        .doc(FirestorePaths.usageDay(uid, day))
        .snapshots()
        .map((snap) => DailyUsage.fromMap(day, snap.data()));
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
      // Date-only query avoids composite type+date index requirements.
      final snap = await _col(uid)
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
          .where('date', isLessThanOrEqualTo: Timestamp.fromDate(end))
          .get();
      final Map<String, double> totals = {};
      for (final doc in snap.docs) {
        final data = doc.data();
        if (data['type'] != type.name) continue;
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
