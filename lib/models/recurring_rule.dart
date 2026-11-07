import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';
import 'package:intl/intl.dart';

import '../core/constants/app_constants.dart';

/// A transaction that repeats: salary, rent, an EMI, a subscription.
///
/// Entries are made by [RecurringRule.dueOccurrences] when the app opens, not
/// by a background job (phones stop those). Each occurrence gets a fixed id
/// ([entryIdFor]), so two devices catching up on the same rule make one
/// entry, not two.
class RecurringRule extends Equatable {
  final String id;
  final TransactionType type;
  final double amount;
  final String categoryId;
  final String categoryName;
  final String? note;
  final String? paymentMethod;
  final String? creditCardId;
  final String? creditCardName;
  final String? accountId;
  final String? accountName;
  final RecurrenceFrequency frequency;

  /// The first occurrence, date and time of day. Later ones keep its day of
  /// the month and its time.
  final DateTime startDate;

  /// The last day an occurrence may fall on. Null repeats for ever.
  final DateTime? endDate;

  /// The latest occurrence an entry has been made for.
  final DateTime? lastGenerated;
  final bool active;
  final DateTime createdAt;

  const RecurringRule({
    required this.id,
    required this.type,
    required this.amount,
    required this.categoryId,
    required this.categoryName,
    this.note,
    this.paymentMethod,
    this.creditCardId,
    this.creditCardName,
    this.accountId,
    this.accountName,
    required this.frequency,
    required this.startDate,
    this.endDate,
    this.lastGenerated,
    this.active = true,
    required this.createdAt,
  });

  /// The [n]th occurrence (0 is [startDate]).
  ///
  /// Monthly and yearly repeats keep the start's day of the month, falling
  /// back to the month's last day when it is shorter: a rent due on the 31st
  /// is due on 30 April and 28 (or 29) February, and back on the 31st in May.
  /// Calendar arithmetic, not hours, so time-zone and daylight-saving changes
  /// never move an occurrence to another day.
  DateTime occurrence(int n) {
    final s = startDate;
    switch (frequency) {
      case RecurrenceFrequency.daily:
        return DateTime(s.year, s.month, s.day + n, s.hour, s.minute);
      case RecurrenceFrequency.weekly:
        return DateTime(s.year, s.month, s.day + 7 * n, s.hour, s.minute);
      case RecurrenceFrequency.monthly:
        return _clamped(s.year, s.month + n, s);
      case RecurrenceFrequency.yearly:
        return _clamped(s.year + n, s.month, s);
    }
  }

  static DateTime _clamped(int year, int month, DateTime s) {
    // DateTime normalises month 13 to January of the next year.
    final first = DateTime(year, month, 1);
    final lastDay = DateTime(first.year, first.month + 1, 0).day;
    final day = s.day > lastDay ? lastDay : s.day;
    return DateTime(first.year, first.month, day, s.hour, s.minute);
  }

  bool _withinEnd(DateTime t) {
    final end = endDate;
    if (end == null) return true;
    return !t.isAfter(DateTime(end.year, end.month, end.day, 23, 59, 59));
  }

  /// The first occurrence after [lastGenerated] (or the start), if any.
  DateTime? nextOccurrence() {
    if (!active) return null;
    final last = lastGenerated;
    var n = 0;
    // Bounded: daily rules over decades are still well under this.
    while (n < 100000) {
      final t = occurrence(n);
      if (!_withinEnd(t)) return null;
      if (last == null || t.isAfter(last)) return t;
      n++;
    }
    return null;
  }

  /// Every occurrence that is due by [now] and has no entry yet, oldest
  /// first.
  List<DateTime> dueOccurrences(DateTime now) {
    final due = <DateTime>[];
    if (!active) return due;
    var next = nextOccurrence();
    var guard = 0;
    while (next != null && !next.isAfter(now) && guard++ < 10000) {
      due.add(next);
      next = copyWith(lastGenerated: next).nextOccurrence();
    }
    return due;
  }

  /// The transaction id for the occurrence on [date].
  String entryIdFor(DateTime date) =>
      'rec-$id-${DateFormat('yyyyMMdd').format(date)}';

  RecurringRule copyWith({
    double? amount,
    String? note,
    DateTime? endDate,
    bool clearEndDate = false,
    DateTime? lastGenerated,
    bool? active,
  }) {
    return RecurringRule(
      id: id,
      type: type,
      amount: amount ?? this.amount,
      categoryId: categoryId,
      categoryName: categoryName,
      note: note ?? this.note,
      paymentMethod: paymentMethod,
      creditCardId: creditCardId,
      creditCardName: creditCardName,
      accountId: accountId,
      accountName: accountName,
      frequency: frequency,
      startDate: startDate,
      endDate: clearEndDate ? null : (endDate ?? this.endDate),
      lastGenerated: lastGenerated ?? this.lastGenerated,
      active: active ?? this.active,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toMap() => {
    'type': type.name,
    'amount': amount,
    'categoryId': categoryId,
    'categoryName': categoryName,
    'note': note,
    'paymentMethod': paymentMethod,
    'creditCardId': creditCardId,
    'creditCardName': creditCardName,
    'accountId': accountId,
    'accountName': accountName,
    'frequency': frequency.name,
    'startDate': Timestamp.fromDate(startDate),
    'endDate': endDate == null ? null : Timestamp.fromDate(endDate!),
    'lastGenerated': lastGenerated == null
        ? null
        : Timestamp.fromDate(lastGenerated!),
    'active': active,
    'createdAt': Timestamp.fromDate(createdAt),
  };

  factory RecurringRule.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    DateTime? ts(Object? v) => (v as Timestamp?)?.toDate();
    return RecurringRule(
      id: doc.id,
      type: TransactionType.values.firstWhere(
        (t) => t.name == d['type'],
        orElse: () => TransactionType.expense,
      ),
      amount: (d['amount'] as num).toDouble(),
      categoryId: d['categoryId'] as String? ?? '',
      categoryName: d['categoryName'] as String? ?? 'Other',
      note: d['note'] as String?,
      paymentMethod: d['paymentMethod'] as String?,
      creditCardId: d['creditCardId'] as String?,
      creditCardName: d['creditCardName'] as String?,
      accountId: d['accountId'] as String?,
      accountName: d['accountName'] as String?,
      frequency: RecurrenceFrequency.values.firstWhere(
        (f) => f.name == d['frequency'],
        orElse: () => RecurrenceFrequency.monthly,
      ),
      startDate: ts(d['startDate']) ?? DateTime.now(),
      endDate: ts(d['endDate']),
      lastGenerated: ts(d['lastGenerated']),
      active: d['active'] as bool? ?? true,
      createdAt: ts(d['createdAt']) ?? DateTime.now(),
    );
  }

  @override
  List<Object?> get props => [
    id,
    type,
    amount,
    categoryId,
    note,
    frequency,
    startDate,
    endDate,
    lastGenerated,
    active,
  ];
}

extension RecurrenceLabel on RecurrenceFrequency {
  String get label => switch (this) {
    RecurrenceFrequency.daily => 'Daily',
    RecurrenceFrequency.weekly => 'Weekly',
    RecurrenceFrequency.monthly => 'Monthly',
    RecurrenceFrequency.yearly => 'Yearly',
  };
}
