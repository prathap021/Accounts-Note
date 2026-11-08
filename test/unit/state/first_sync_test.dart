import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:accounts_note/core/sync/sync_manager.dart';
import 'package:accounts_note/data/repositories/transaction_repository.dart';
import 'package:accounts_note/models/transaction_model.dart';
import 'package:accounts_note/providers/sync_provider.dart';
import 'package:accounts_note/providers/transaction_provider.dart';

import '../../support/fixtures.dart';

class _Connectivity implements Connectivity {
  _Connectivity({required this.online});
  bool online;
  final _changes = StreamController<List<ConnectivityResult>>.broadcast();

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => [
    online ? ConnectivityResult.wifi : ConnectivityResult.none,
  ];

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged => _changes.stream;
}

/// The dashboard shimmers on a first sign-in until the cloud arrives, and
/// shows local data at once otherwise.
void main() {
  group('awaitingFirstCloudDataProvider', () {
    bool awaiting({
      required bool storeReady,
      required List<TransactionModel> local,
      required bool firstSyncDone,
    }) {
      final container = ProviderContainer(
        overrides: [
          localStoreReadyProvider.overrideWith(
            (ref) => storeReady ? Future.value(true) : Completer<bool>().future,
          ),
          allTransactionsStreamProvider.overrideWith(
            (ref) => Stream.value(local),
          ),
          currentSyncStateProvider.overrideWithValue(
            SyncState(firstSyncDone: firstSyncDone),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.listen(awaitingFirstCloudDataProvider, (_, _) {});
      return container.read(awaitingFirstCloudDataProvider);
    }

    Future<bool> settled({
      required bool storeReady,
      required List<TransactionModel> local,
      required bool firstSyncDone,
    }) async {
      final container = ProviderContainer(
        overrides: [
          localStoreReadyProvider.overrideWith(
            (ref) => storeReady ? Future.value(true) : Completer<bool>().future,
          ),
          allTransactionsStreamProvider.overrideWith(
            (ref) => Stream.value(local),
          ),
          currentSyncStateProvider.overrideWithValue(
            SyncState(firstSyncDone: firstSyncDone),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.listen(awaitingFirstCloudDataProvider, (_, _) {});
      container.listen(allTransactionsStreamProvider, (_, _) {});
      await Future<void>.delayed(Duration.zero);
      return container.read(awaitingFirstCloudDataProvider);
    }

    test('shimmers while the local box is still opening', () {
      expect(
        awaiting(storeReady: false, local: const [], firstSyncDone: false),
        isTrue,
      );
    });

    test('a first sign-in shimmers until the first sync finishes', () async {
      expect(
        await settled(storeReady: true, local: const [], firstSyncDone: false),
        isTrue,
      );
      expect(
        await settled(storeReady: true, local: const [], firstSyncDone: true),
        isFalse,
        reason: 'truly empty: the empty state is right',
      );
    });

    test('data already on the device shows at once, sync or not', () async {
      expect(
        await settled(
          storeReady: true,
          local: [txFixture()],
          firstSyncDone: false,
        ),
        isFalse,
      );
    });
  });

  group('SyncManager.firstSyncDone', () {
    final harness = HiveHarness();
    setUp(harness.setUp);
    tearDown(harness.tearDown);

    SyncManager manager(_Connectivity connectivity) => SyncManager(
      store: harness.store,
      repository: TransactionRepository(firestore: FakeFirebaseFirestore()),
      connectivity: connectivity,
    );

    test('is set once the first sync after start has pulled', () async {
      final m = manager(_Connectivity(online: true));
      addTearDown(m.dispose);
      expect(m.state.firstSyncDone, isFalse);
      final done = m.stateStream.firstWhere((s) => s.firstSyncDone);
      await m.start();
      expect((await done).phase, SyncPhase.idle);
    });

    test('is set straight away when starting offline', () async {
      final m = manager(_Connectivity(online: false));
      addTearDown(m.dispose);
      await m.start();
      expect(m.state.firstSyncDone, isTrue);
      expect(m.state.phase, SyncPhase.offline);
    });

    test('starts over for the next session', () async {
      final m = manager(_Connectivity(online: false));
      addTearDown(m.dispose);
      await m.start();
      expect(m.state.firstSyncDone, isTrue);
      await m.stop();
      final next = m.stateStream.first;
      unawaited(m.start());
      expect((await next).firstSyncDone, isFalse);
    });
  });
}
