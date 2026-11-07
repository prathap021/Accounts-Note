import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:income_expense_tracker/core/constants/app_constants.dart';
import 'package:income_expense_tracker/data/local/sync_status.dart';
import 'package:income_expense_tracker/data/repositories/account_repository.dart';
import 'package:income_expense_tracker/models/account_model.dart';
import 'package:income_expense_tracker/models/transaction_model.dart';
import 'package:income_expense_tracker/providers/account_provider.dart';

void main() {
  final t0 = DateTime(2026, 11, 1, 10);

  AccountModel account(String id, double opening, [AccountKind? kind]) =>
      AccountModel(
        id: id,
        name: id,
        kind: kind ?? AccountKind.bank,
        openingBalance: opening,
        createdAt: t0,
      );

  TransactionModel tx(
    TransactionType type,
    double amount, {
    String? account,
    String? card,
    PendingOp op = PendingOp.none,
  }) => TransactionModel(
    id: '${type.name}$amount$account$card',
    type: type,
    amount: amount,
    categoryId: 'c',
    categoryName: 'C',
    date: t0,
    accountId: account,
    accountName: account,
    creditCardId: card,
    createdAt: t0,
    updatedAt: t0,
    pendingOp: op,
  );

  TransferModel move(String from, String to, double amount) => TransferModel(
    id: '$from-$to',
    fromAccountId: from,
    toAccountId: to,
    fromAccountName: from,
    toAccountName: to,
    amount: amount,
    date: t0,
    createdAt: t0,
  );

  group('account balances', () {
    test('opening balance plus income minus expenses', () {
      final b = accountBalancesFor(
        [account('sbi', 10000), account('cash', 0, AccountKind.cash)],
        [
          tx(TransactionType.income, 50000, account: 'sbi'),
          tx(TransactionType.expense, 1200, account: 'sbi'),
          tx(TransactionType.expense, 300, account: 'cash'),
          // Not against any account: counts nowhere.
          tx(TransactionType.expense, 999),
        ],
        const [],
      );
      expect(b, {'sbi': 58800, 'cash': -300});
    });

    test('a transfer moves money without changing the total', () {
      final accounts = [account('sbi', 10000), account('cash', 500)];
      final before = accountBalancesFor(accounts, const [], const []);
      final after = accountBalancesFor(accounts, const [], [
        move('sbi', 'cash', 2000),
      ]);
      expect(after, {'sbi': 8000, 'cash': 2500});
      double sum(Map<String, double> m) => m.values.reduce((a, b) => a + b);
      expect(sum(after), sum(before));
    });

    test('card charges, deleted entries and gone accounts are left out', () {
      final b = accountBalancesFor(
        [account('sbi', 100)],
        [
          tx(TransactionType.expense, 40, account: 'sbi', card: 'hdfc'),
          tx(TransactionType.expense, 10, account: 'sbi', op: PendingOp.delete),
          tx(TransactionType.income, 70, account: 'closed'),
        ],
        [move('closed', 'sbi', 5)],
      );
      expect(b, {'sbi': 105});
    });
  });

  group('account repository', () {
    late FakeFirebaseFirestore db;
    late AccountRepository repo;

    setUp(() {
      db = FakeFirebaseFirestore();
      repo = AccountRepository(firestore: db);
    });

    test('accounts and transfers round-trip through Firestore', () async {
      final sbi = (await repo.addAccount(
        'u',
        account('', 1500.5, AccountKind.bank).copyWith(name: 'SBI savings'),
      )).when(success: (a) => a, failure: (f) => throw f);
      expect(sbi.id, isNotEmpty);
      final cash = (await repo.addAccount(
        'u',
        account('', 0, AccountKind.cash).copyWith(name: 'Cash'),
      )).when(success: (a) => a, failure: (f) => throw f);

      final saved = await repo.addTransfer(
        'u',
        TransferModel(
          id: '',
          fromAccountId: sbi.id,
          toAccountId: cash.id,
          fromAccountName: sbi.name,
          toAccountName: cash.name,
          amount: 500,
          date: t0,
          note: 'ATM',
          createdAt: t0,
        ),
      );
      expect(saved.isSuccess, isTrue);

      final accounts = await repo.watchAccounts('u').first;
      expect(accounts.map((a) => a.name), ['SBI savings', 'Cash']);
      expect(accounts.first.kind, AccountKind.bank);
      expect(accounts.first.openingBalance, 1500.5);

      final transfers = await repo.watchTransfers('u').first;
      expect(transfers.single.note, 'ATM');
      expect(transfers.single.toAccountName, 'Cash');

      await repo.deleteTransfer('u', transfers.single.id);
      expect(await repo.watchTransfers('u').first, isEmpty);
    });

    test('a transaction keeps its account through the cloud and Hive', () {
      final t = tx(TransactionType.expense, 80, account: 'sbi');
      expect(t.toMap()['accountId'], 'sbi');
      final back = TransactionModel.fromLocalMap(t.toLocalMap());
      expect(back.accountId, 'sbi');
      expect(back.accountName, 'sbi');
      expect(t.copyWith(clearAccount: true).accountId, isNull);
      // Written as null when cleared, so a merge upsert removes it.
      expect(
        t.copyWith(clearAccount: true).toMap().containsKey('accountId'),
        isTrue,
      );
    });
  });
}
