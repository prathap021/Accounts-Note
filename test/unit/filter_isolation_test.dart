import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:income_expense_tracker/core/constants/app_constants.dart';
import 'package:income_expense_tracker/core/sync/sync_manager.dart';
import 'package:income_expense_tracker/data/repositories/offline_transaction_repository.dart';
import 'package:income_expense_tracker/data/repositories/transaction_repository.dart';
import 'package:income_expense_tracker/providers/sync_provider.dart';
import 'package:income_expense_tracker/providers/transaction_provider.dart';

import '../support/fixtures.dart';

/// The Activity filter must stay on the Activity screen.
///
/// Both lists used to read the same filtered provider, so narrowing Activity
/// to "Income" silently emptied the dashboard's list and skewed anything else
/// reading it.
void main() {
  late HiveHarness hive;
  late ProviderContainer container;

  setUp(() async {
    hive = HiveHarness();
    await hive.setUp();

    final firestore = FakeFirebaseFirestore();
    final repo = OfflineTransactionRepository(
      store: hive.store,
      remote: TransactionRepository(firestore: firestore),
      syncManager: SyncManager(
        store: hive.store,
        repository: TransactionRepository(firestore: firestore),
      ),
      autoSync: false,
    );

    container = ProviderContainer(overrides: [
      // Synchronous so the streams start on the first read; an async
      // override leaves them emitting an empty list forever in a test.
      localStoreReadyProvider.overrideWith((ref) => true),
      offlineTransactionRepositoryProvider.overrideWithValue(repo),
    ]);
    addTearDown(container.dispose);

    await hive.store.putAll([
      txFixture(id: 'income', type: TransactionType.income, amount: 5000),
      txFixture(id: 'expense-a', amount: 70),
      txFixture(id: 'expense-b', amount: 30),
    ]);

    // Materialise the providers so their streams are listening.
    container.listen(allTransactionsStreamProvider, (_, _) {});
    container.listen(transactionsStreamProvider, (_, _) {});
  });

  tearDown(() => hive.tearDown());

  Future<List<String>> idsFrom(
    StreamProvider<List<dynamic>> provider,
  ) async {
    // Let the store's watch() deliver before reading.
    await Future<void>.delayed(const Duration(milliseconds: 40));
    final items = container.read(provider).value ?? const [];
    return items.map((t) => t.id as String).toList();
  }

  test('with no filter, both lists agree', () async {
    expect((await idsFrom(allTransactionsStreamProvider)).length, 3);
    expect((await idsFrom(transactionsStreamProvider)).length, 3);
  });

  test('a filter narrows Activity but not the unfiltered list', () async {
    container
        .read(transactionFilterProvider.notifier)
        .update(const TransactionFilter(type: TransactionType.income));

    final activity = await idsFrom(transactionsStreamProvider);
    final everything = await idsFrom(allTransactionsStreamProvider);

    expect(activity, ['income'], reason: 'Activity honours the filter');
    expect(everything.length, 3,
        reason: 'the dashboard must not shrink because another tab filtered');
  });

  test('a search on Activity leaves the unfiltered list alone', () async {
    container
        .read(transactionFilterProvider.notifier)
        .update(const TransactionFilter(searchQuery: 'nothing-matches-this'));

    expect(await idsFrom(transactionsStreamProvider), isEmpty);
    expect((await idsFrom(allTransactionsStreamProvider)).length, 3,
        reason: 'an empty search result must not empty the dashboard');
  });

  test('clearing the filter restores Activity', () async {
    final notifier = container.read(transactionFilterProvider.notifier);
    notifier.update(const TransactionFilter(type: TransactionType.income));
    expect((await idsFrom(transactionsStreamProvider)).length, 1);

    notifier.update(const TransactionFilter());
    expect((await idsFrom(transactionsStreamProvider)).length, 3);
  });
}
