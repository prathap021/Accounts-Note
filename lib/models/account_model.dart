import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

/// What kind of place the money sits in. Only changes the icon and label.
enum AccountKind {
  cash('Cash', Icons.payments_outlined),
  bank('Bank', Icons.account_balance_outlined),
  upi('UPI', Icons.qr_code_2_rounded),
  wallet('Wallet', Icons.account_balance_wallet_outlined);

  const AccountKind(this.label, this.icon);
  final String label;
  final IconData icon;

  static AccountKind fromName(String? name) => AccountKind.values.firstWhere(
    (k) => k.name == name,
    orElse: () => AccountKind.bank,
  );
}

/// Somewhere the user keeps money: cash in hand, a bank account, a UPI
/// balance or a wallet. Its balance is the opening balance plus the income
/// and minus the expenses put against it, adjusted by transfers.
///
/// Credit cards are kept apart (see `CreditCardModel`): a card holds debt,
/// not money.
class AccountModel extends Equatable {
  final String id;
  final String name;
  final AccountKind kind;

  /// What was in the account when the user started tracking it. May be
  /// negative, for an overdrawn account.
  final double openingBalance;
  final DateTime createdAt;

  const AccountModel({
    required this.id,
    required this.name,
    required this.kind,
    this.openingBalance = 0,
    required this.createdAt,
  });

  // Mirror isValidAccount in firestore.rules.
  static const maxNameLength = 50;
  static const maxAmount = 1e12;

  AccountModel copyWith({
    String? id,
    String? name,
    AccountKind? kind,
    double? openingBalance,
  }) => AccountModel(
    id: id ?? this.id,
    name: name ?? this.name,
    kind: kind ?? this.kind,
    openingBalance: openingBalance ?? this.openingBalance,
    createdAt: createdAt,
  );

  Map<String, dynamic> toMap() => {
    'name': name,
    'kind': kind.name,
    'openingBalance': openingBalance,
    'createdAt': Timestamp.fromDate(createdAt),
  };

  factory AccountModel.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return AccountModel(
      id: doc.id,
      name: data['name'] as String? ?? 'Account',
      kind: AccountKind.fromName(data['kind'] as String?),
      openingBalance: (data['openingBalance'] as num?)?.toDouble() ?? 0,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  @override
  List<Object?> get props => [id, name, kind, openingBalance, createdAt];
}

/// Money moved from one of the user's accounts to another: cash withdrawn
/// from the bank, a wallet top-up. Neither income nor expense, so it never
/// shows in totals, reports or budgets, and it does not use the daily
/// entry allowance.
class TransferModel extends Equatable {
  final String id;
  final String fromAccountId;
  final String toAccountId;

  /// Names at the time, so the history reads right after a rename or delete.
  final String fromAccountName;
  final String toAccountName;
  final double amount;
  final DateTime date;
  final String? note;
  final DateTime createdAt;

  const TransferModel({
    required this.id,
    required this.fromAccountId,
    required this.toAccountId,
    required this.fromAccountName,
    required this.toAccountName,
    required this.amount,
    required this.date,
    this.note,
    required this.createdAt,
  });

  TransferModel withId(String id) => TransferModel(
    id: id,
    fromAccountId: fromAccountId,
    toAccountId: toAccountId,
    fromAccountName: fromAccountName,
    toAccountName: toAccountName,
    amount: amount,
    date: date,
    note: note,
    createdAt: createdAt,
  );

  Map<String, dynamic> toMap() => {
    'fromAccountId': fromAccountId,
    'toAccountId': toAccountId,
    'fromAccountName': fromAccountName,
    'toAccountName': toAccountName,
    'amount': amount,
    'date': Timestamp.fromDate(date),
    'note': note,
    'createdAt': Timestamp.fromDate(createdAt),
  };

  factory TransferModel.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return TransferModel(
      id: doc.id,
      fromAccountId: data['fromAccountId'] as String? ?? '',
      toAccountId: data['toAccountId'] as String? ?? '',
      fromAccountName: data['fromAccountName'] as String? ?? 'Account',
      toAccountName: data['toAccountName'] as String? ?? 'Account',
      amount: (data['amount'] as num?)?.toDouble() ?? 0,
      date: (data['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
      note: data['note'] as String?,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  @override
  List<Object?> get props => [
    id,
    fromAccountId,
    toAccountId,
    fromAccountName,
    toAccountName,
    amount,
    date,
    note,
  ];
}
