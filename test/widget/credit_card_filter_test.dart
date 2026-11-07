import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:income_expense_tracker/core/constants/app_constants.dart';
import 'package:income_expense_tracker/core/sync/sync_manager.dart';
import 'package:income_expense_tracker/core/theme/app_theme.dart';
import 'package:income_expense_tracker/data/local/transaction_local_store.dart';
import 'package:income_expense_tracker/data/repositories/category_repository.dart';
import 'package:income_expense_tracker/data/repositories/credit_card_repository.dart';
import 'package:income_expense_tracker/data/repositories/offline_transaction_repository.dart';
import 'package:income_expense_tracker/data/repositories/transaction_repository.dart';
import 'package:income_expense_tracker/features/transactions/transactions_screen.dart';
import 'package:income_expense_tracker/models/transaction_model.dart';
import 'package:income_expense_tracker/providers/auth_provider.dart';
import 'package:income_expense_tracker/providers/category_provider.dart';
import 'package:income_expense_tracker/providers/credit_card_provider.dart';
import 'package:income_expense_tracker/providers/settings_provider.dart';
import 'package:income_expense_tracker/providers/sync_provider.dart';
import 'package:income_expense_tracker/providers/transaction_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fixtures.dart';

/// The point of the credit card feature: narrow Activity to a card (or any
/// other filter) and see what it adds up to — in the filter sheet as chips are
/// tapped, and on the list once applied.
void main() {
  late FakeFirebaseFirestore firestore;
  late SharedPreferences prefs;

  final hdfc = creditCardFixture();
  final sbi = creditCardFixture(
    id: 'card-sbi',
    name: 'SBI SimplyClick',
    last4: '9876',
    color: 0xFFBE123C,
  );

  final ledger = [
    cardTxFixture(hdfc, id: 'h1', amount: 1200, date: DateTime(2026, 9, 14, 12)),
    cardTxFixture(hdfc,
        id: 'h2',
        amount: 800,
        categoryName: 'Transport',
        date: DateTime(2026, 9, 12)),
    cardTxFixture(sbi,
        id: 's1',
        amount: 2500,
        categoryName: 'Shopping',
        date: DateTime(2026, 9, 13)),
    txFixture(id: 'cash', amount: 150, date: DateTime(2026, 9, 14, 9)),
  ];

  setUp(() async {
    firestore = FakeFirebaseFirestore();
    for (final card in [hdfc, sbi]) {
      await firestore
          .collection(FirestorePaths.creditCards(testUid))
          .doc(card.id)
          .set(card.toMap());
    }
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  Future<void> pumpActivity(
    WidgetTester tester, {
    TransactionFilter filter = const TransactionFilter(),
    List<TransactionModel> extra = const [],
  }) async {
    // Tall enough that the filter sheet fits without scrolling.
    tester.view.physicalSize = const Size(430, 1500);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final store = _MemoryStore([...ledger, ...extra]);
    final remote = TransactionRepository(firestore: firestore);
    final repo = OfflineTransactionRepository(
      store: store,
      remote: remote,
      syncManager: SyncManager(store: store, repository: remote),
      autoSync: false,
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        currentUidProvider.overrideWithValue(testUid),
        localStoreReadyProvider.overrideWith((ref) => true),
        offlineTransactionRepositoryProvider.overrideWithValue(repo),
        currentSyncStateProvider.overrideWithValue(const SyncState()),
        categoryRepositoryProvider
            .overrideWithValue(CategoryRepository(firestore: firestore)),
        creditCardRepositoryProvider
            .overrideWithValue(CreditCardRepository(firestore: firestore)),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const TransactionsScreen(),
      ),
    ));

    ProviderScope.containerOf(tester.element(find.byType(TransactionsScreen)))
        .read(transactionFilterProvider.notifier)
        .update(filter);
    await tester.pumpAndSettle();
  }

  Future<void> openFilterSheet(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.tune_rounded));
    await tester.pumpAndSettle();
  }

  Future<void> tapChip(WidgetTester tester, String label) async {
    await tester.tap(find.widgetWithText(ChoiceChip, label));
    await tester.pumpAndSettle();
  }

  /// Asserts against the totals card alone, found by its heading — the same
  /// amount can also appear in a day header, which must not satisfy this.
  void expectTotal(String heading, String amount, String count) {
    final card =
        find.ancestor(of: find.text(heading), matching: find.byType(AppCard));
    expect(card, findsOneWidget, reason: 'one "$heading" card');
    expect(find.descendant(of: card, matching: find.text(amount)),
        findsOneWidget);
    expect(find.descendant(of: card, matching: find.text(count)),
        findsOneWidget);
  }

  testWidgets('filtering by a card lists its charges and their total',
      (tester) async {
    await pumpActivity(
      tester,
      filter: const TransactionFilter(creditCardId: 'card-hdfc'),
    );

    expectTotal('TOTAL SPENT', '₹2,000.00', '2 transactions');
    expect(find.widgetWithText(InputChip, 'HDFC Millennia ••4321'),
        findsOneWidget,
        reason: 'the card filter is shown, and removable, by name');
    expect(find.text('Shopping'), findsNothing,
        reason: 'the SBI charge is not on this card');
  });

  testWidgets('removing the card chip drops the filter and its total',
      (tester) async {
    await pumpActivity(
      tester,
      filter: const TransactionFilter(creditCardId: 'card-hdfc'),
    );

    await tester.tap(find.descendant(
      of: find.widgetWithText(InputChip, 'HDFC Millennia ••4321'),
      matching: find.byIcon(Icons.close_rounded),
    ));
    await tester.pumpAndSettle();

    expect(find.text('TOTAL SPENT'), findsNothing);
    expect(find.text('Shopping'), findsOneWidget);
  });

  testWidgets('no total is shown while nothing is filtered', (tester) async {
    await pumpActivity(tester);

    expect(find.textContaining('TOTAL'), findsNothing);
  });

  testWidgets('the sheet totals the selection live, before Apply',
      (tester) async {
    await pumpActivity(tester);
    await openFilterSheet(tester);

    expect(find.text('Tap any filter to see its total here.'), findsOneWidget);

    await tapChip(tester, 'SBI SimplyClick ••9876');
    expectTotal('TOTAL SPENT', '₹2,500.00', '1 transaction');

    await tapChip(tester, 'All cards');
    expectTotal('TOTAL SPENT', '₹4,500.00', '3 transactions');
  });

  testWidgets('Apply shows the same total the sheet previewed',
      (tester) async {
    await pumpActivity(tester);
    await openFilterSheet(tester);
    await tapChip(tester, 'All cards');

    await tester.tap(find.widgetWithText(FilledButton, 'Apply'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(InputChip, 'All credit cards'), findsOneWidget);
    expectTotal('TOTAL SPENT', '₹4,500.00', '3 transactions');
  });

  testWidgets('a refund on the card shows the net, with both sides',
      (tester) async {
    await pumpActivity(
      tester,
      filter: const TransactionFilter(creditCardId: 'card-hdfc'),
      extra: [
        cardTxFixture(hdfc,
            id: 'refund',
            type: TransactionType.income,
            amount: 200,
            date: DateTime(2026, 9, 11)),
      ],
    );

    expectTotal('NET TOTAL', '−₹1,800.00', '3 transactions');
  });

  testWidgets('a date range includes everything on its last day',
      (tester) async {
    // The range picker returns midnight at the start of the last day. Before
    // the sheet widened it, this range dropped both entries on the 14th.
    await pumpActivity(
      tester,
      filter: TransactionFilter(
        startDate: DateTime(2026, 9, 14),
        endDate: DateTime(2026, 9, 14),
      ),
    );
    await openFilterSheet(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Apply'));
    await tester.pumpAndSettle();

    expectTotal('TOTAL SPENT', '₹1,350.00', '2 transactions');
  });
}

/// Serves a fixed ledger from memory.
///
/// Hive's on-disk behaviour is covered by the data tests. Here it would put
/// real I/O under the widget tester's fake clock — and a failing widget test
/// leaves its tree mounted, so closing the box in tearDown would then hang
/// the run instead of reporting the failure.
class _MemoryStore extends TransactionLocalStore {
  final List<TransactionModel> _items;

  _MemoryStore(Iterable<TransactionModel> items)
      : _items = [...items]..sort((a, b) => b.date.compareTo(a.date));

  @override
  List<TransactionModel> getAll() => _items;

  @override
  Stream<List<TransactionModel>> watch() => Stream.value(_items);
}
