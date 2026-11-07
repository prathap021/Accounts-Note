import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';
import '../core/constants/app_constants.dart';
import '../data/local/sync_status.dart';

class TransactionModel extends Equatable {
  final String id;
  final TransactionType type;
  final double amount;
  final String categoryId;
  final String categoryName; // denormalized for fast list rendering
  final String? note;
  final DateTime date;
  final String? paymentMethod;

  /// The credit card this was charged to, when the payment method is
  /// [kCreditCardPaymentMethod].
  final String? creditCardId;

  /// The card's display name at the time — denormalized like [categoryName],
  /// so history still reads correctly after the card is renamed or deleted.
  final String? creditCardName;
  final bool isRecurring;
  final String? recurringId; // link back to the recurring template, if any
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Where this record stands with the cloud. Owned by the local store.
  final SyncStatus syncStatus;

  /// The cloud write this record still owes, if any.
  final PendingOp pendingOp;

  /// Why the last push failed, kept for diagnostics and the retry UI.
  final String? lastSyncError;
  final int retryCount;

  const TransactionModel({
    required this.id,
    required this.type,
    required this.amount,
    required this.categoryId,
    required this.categoryName,
    this.note,
    required this.date,
    this.paymentMethod,
    this.creditCardId,
    this.creditCardName,
    this.isRecurring = false,
    this.recurringId,
    required this.createdAt,
    required this.updatedAt,
    this.syncStatus = SyncStatus.synced,
    this.pendingOp = PendingOp.none,
    this.lastSyncError,
    this.retryCount = 0,
  });

  /// Kept for the UI, which shows a small indicator while a row is in flight.
  bool get pendingSync =>
      syncStatus == SyncStatus.pending || syncStatus == SyncStatus.syncing;

  /// Tombstoned locally — hidden from lists until the cloud delete lands.
  bool get isDeleted => pendingOp == PendingOp.delete;

  /// Charged to a credit card rather than settled in cash.
  ///
  /// This is the line between the two halves of the dashboard. Swiping a card
  /// moves no money out of the user's pocket — it creates debt the card issuer
  /// bills later — so a card charge must not reduce the available balance or
  /// count as a cash expense. It is tracked against the card instead.
  bool get isOnCard => creditCardId != null;

  /// Settled in cash, bank or UPI — money that actually moved.
  bool get isCash => !isOnCard;

  TransactionModel copyWith({
    String? id,
    TransactionType? type,
    double? amount,
    String? categoryId,
    String? categoryName,
    String? note,
    DateTime? date,
    String? paymentMethod,
    String? creditCardId,
    String? creditCardName,
    bool? isRecurring,
    String? recurringId,
    DateTime? createdAt,
    DateTime? updatedAt,
    SyncStatus? syncStatus,
    PendingOp? pendingOp,
    String? lastSyncError,
    bool clearSyncError = false,
    int? retryCount,
  }) {
    return TransactionModel(
      id: id ?? this.id,
      type: type ?? this.type,
      amount: amount ?? this.amount,
      categoryId: categoryId ?? this.categoryId,
      categoryName: categoryName ?? this.categoryName,
      note: note ?? this.note,
      date: date ?? this.date,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      creditCardId: creditCardId ?? this.creditCardId,
      creditCardName: creditCardName ?? this.creditCardName,
      isRecurring: isRecurring ?? this.isRecurring,
      recurringId: recurringId ?? this.recurringId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      syncStatus: syncStatus ?? this.syncStatus,
      pendingOp: pendingOp ?? this.pendingOp,
      lastSyncError:
          clearSyncError ? null : (lastSyncError ?? this.lastSyncError),
      retryCount: retryCount ?? this.retryCount,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'type': type.name,
      'amount': amount,
      'categoryId': categoryId,
      'categoryName': categoryName,
      'note': note,
      'date': Timestamp.fromDate(date),
      'paymentMethod': paymentMethod,
      // Written even when null: the sync upsert merges, so leaving the keys
      // out would keep a card on an entry the user moved back to cash.
      'creditCardId': creditCardId,
      'creditCardName': creditCardName,
      'isRecurring': isRecurring,
      'recurringId': recurringId,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  /// Hive-safe representation: primitives only, dates as epoch millis, so no
  /// generated TypeAdapter is needed and the box stays readable across
  /// model changes.
  Map<String, dynamic> toLocalMap() {
    return {
      'id': id,
      'type': type.name,
      'amount': amount,
      'categoryId': categoryId,
      'categoryName': categoryName,
      'note': note,
      'date': date.millisecondsSinceEpoch,
      'paymentMethod': paymentMethod,
      'creditCardId': creditCardId,
      'creditCardName': creditCardName,
      'isRecurring': isRecurring,
      'recurringId': recurringId,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
      'syncStatus': syncStatus.name,
      'pendingOp': pendingOp.name,
      'lastSyncError': lastSyncError,
      'retryCount': retryCount,
    };
  }

  factory TransactionModel.fromLocalMap(Map<dynamic, dynamic> map) {
    DateTime dateFrom(Object? value) => DateTime.fromMillisecondsSinceEpoch(
          (value as num?)?.toInt() ?? 0,
        );

    return TransactionModel(
      id: map['id'] as String? ?? '',
      type: TransactionType.values.firstWhere(
        (t) => t.name == map['type'],
        orElse: () => TransactionType.expense,
      ),
      amount: (map['amount'] as num?)?.toDouble() ?? 0,
      categoryId: map['categoryId'] as String? ?? '',
      categoryName: map['categoryName'] as String? ?? 'Other',
      note: map['note'] as String?,
      date: dateFrom(map['date']),
      paymentMethod: map['paymentMethod'] as String?,
      creditCardId: map['creditCardId'] as String?,
      creditCardName: map['creditCardName'] as String?,
      isRecurring: map['isRecurring'] as bool? ?? false,
      recurringId: map['recurringId'] as String?,
      createdAt: dateFrom(map['createdAt']),
      updatedAt: dateFrom(map['updatedAt']),
      syncStatus: SyncStatus.fromName(map['syncStatus'] as String?),
      pendingOp: PendingOp.fromName(map['pendingOp'] as String?),
      lastSyncError: map['lastSyncError'] as String?,
      retryCount: (map['retryCount'] as num?)?.toInt() ?? 0,
    );
  }

  factory TransactionModel.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return TransactionModel(
      id: doc.id,
      type: TransactionType.values.firstWhere(
        (t) => t.name == data['type'],
        orElse: () => TransactionType.expense,
      ),
      amount: (data['amount'] as num).toDouble(),
      categoryId: data['categoryId'] as String? ?? '',
      categoryName: data['categoryName'] as String? ?? 'Other',
      note: data['note'] as String?,
      date: (data['date'] as Timestamp).toDate(),
      paymentMethod: data['paymentMethod'] as String?,
      creditCardId: data['creditCardId'] as String?,
      creditCardName: data['creditCardName'] as String?,
      isRecurring: data['isRecurring'] as bool? ?? false,
      recurringId: data['recurringId'] as String?,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      // Anything read back from Firestore is, by definition, in the cloud.
      syncStatus: SyncStatus.synced,
    );
  }

  @override
  List<Object?> get props => [
        id,
        type,
        amount,
        categoryId,
        categoryName,
        note,
        date,
        paymentMethod,
        creditCardId,
        creditCardName,
        isRecurring,
        recurringId,
        createdAt,
        updatedAt,
      ];
}
