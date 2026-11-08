import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:accounts_note/core/constants/app_constants.dart';
import 'package:accounts_note/core/sync/sync_manager.dart';
import 'package:accounts_note/data/repositories/category_repository.dart';
import 'package:accounts_note/data/repositories/offline_transaction_repository.dart';
import 'package:accounts_note/data/repositories/transaction_repository.dart';
import 'package:accounts_note/models/category_model.dart';
import 'package:accounts_note/providers/auth_provider.dart';
import 'package:accounts_note/providers/category_provider.dart';
import 'package:accounts_note/providers/sync_provider.dart';

import '../../support/fixtures.dart';

/// Removing a category moves its transactions to "Other", so nothing is
/// left pointing at a category that no longer exists.
void main() {
  final hive = HiveHarness();
  late FakeFirebaseFirestore firestore;
  late ProviderContainer container;

  setUp(() async {
    await hive.setUp();
    firestore = FakeFirebaseFirestore();
    final remote = TransactionRepository(firestore: firestore);
    container = ProviderContainer(
      overrides: [
        currentUidProvider.overrideWithValue(testUid),
        categoryRepositoryProvider.overrideWithValue(
          CategoryRepository(firestore: firestore),
        ),
        offlineTransactionRepositoryProvider.overrideWithValue(
          OfflineTransactionRepository(
            store: hive.store,
            remote: remote,
            syncManager: SyncManager(store: hive.store, repository: remote),
            autoSync: false,
          ),
        ),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await hive.tearDown();
  });

  Future<CategoryModel> category(String name) async {
    final ref = firestore.collection(FirestorePaths.categories(testUid)).doc();
    final c = CategoryModel(
      id: ref.id,
      name: name,
      icon: 'category',
      color: 0,
      type: TransactionType.expense,
      createdAt: DateTime(2026),
    );
    await ref.set(c.toMap());
    return c;
  }

  test('its transactions move to Other, and it is deleted', () async {
    final pets = await category('Pets');
    final other = await category('Other');
    await hive.store.put(
      txFixture(id: 'a', categoryId: pets.id, categoryName: 'Pets'),
    );
    await hive.store.put(
      txFixture(id: 'b', categoryId: pets.id, categoryName: 'Pets'),
    );
    await hive.store.put(txFixture(id: 'c', categoryName: 'Food'));

    final moved = await container
        .read(categoryActionsProvider.notifier)
        .removeCategory(pets);

    expect(moved, 2);
    expect(hive.store.getById('a')!.categoryId, other.id);
    expect(hive.store.getById('a')!.categoryName, 'Other');
    expect(hive.store.getById('c')!.categoryName, 'Food', reason: 'untouched');
    final left = await firestore
        .collection(FirestorePaths.categories(testUid))
        .get();
    expect(left.docs.map((d) => d['name']), ['Other']);
  });

  test('"Other" itself cannot be removed', () async {
    final other = await category('Other');
    expect(CategoryActionsNotifier.isFallback(other), isTrue);
    expect(
      await container
          .read(categoryActionsProvider.notifier)
          .removeCategory(other),
      isNull,
    );
  });
}
