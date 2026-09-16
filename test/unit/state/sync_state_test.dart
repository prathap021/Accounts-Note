import 'package:flutter_test/flutter_test.dart';
import 'package:income_expense_tracker/core/sync/sync_manager.dart';
import 'package:income_expense_tracker/data/local/sync_status.dart';

/// The one-word status the user sees. Getting this wrong tells people their
/// data is safe when it is not, so every phase is pinned.
void main() {
  group('label', () {
    test('idle with nothing queued reads Synced', () {
      expect(const SyncState(phase: SyncPhase.idle).label, 'Synced');
    });

    test('idle with queued work reads Pending', () {
      expect(
        const SyncState(phase: SyncPhase.idle, pendingCount: 2).label,
        'Pending',
      );
    });

    test('syncing reads Syncing', () {
      expect(const SyncState(phase: SyncPhase.syncing).label, 'Syncing');
    });

    test('offline with nothing queued reads Offline', () {
      expect(const SyncState(phase: SyncPhase.offline).label, 'Offline');
    });

    test('offline with queued work reads Pending', () {
      expect(
        const SyncState(phase: SyncPhase.offline, pendingCount: 1).label,
        'Pending',
      );
    });

    test('failed reads Failed', () {
      expect(const SyncState(phase: SyncPhase.failed).label, 'Failed');
    });
  });

  group('hasWork', () {
    test('is false when everything is settled', () {
      expect(const SyncState().hasWork, isFalse);
    });

    test('is true with pending or failed records', () {
      expect(const SyncState(pendingCount: 1).hasWork, isTrue);
      expect(const SyncState(failedCount: 1).hasWork, isTrue);
    });
  });

  test('copyWith changes only what it is given', () {
    const original = SyncState(
      phase: SyncPhase.idle,
      isOnline: true,
      pendingCount: 3,
    );

    final updated = original.copyWith(phase: SyncPhase.syncing);

    expect(updated.phase, SyncPhase.syncing);
    expect(updated.pendingCount, 3);
    expect(updated.isOnline, isTrue);
  });

  group('SyncStatus parsing', () {
    test('round-trips known names', () {
      for (final status in SyncStatus.values) {
        expect(SyncStatus.fromName(status.name), status);
      }
    });

    test('unknown or missing names are treated as pending, never synced', () {
      expect(SyncStatus.fromName('nonsense'), SyncStatus.pending);
      expect(SyncStatus.fromName(null), SyncStatus.pending);
    });

    test('only synced counts as settled', () {
      expect(SyncStatus.synced.isSettled, isTrue);
      expect(SyncStatus.pending.isSettled, isFalse);
      expect(SyncStatus.failed.isSettled, isFalse);
    });
  });

  group('PendingOp parsing', () {
    test('round-trips known names', () {
      for (final op in PendingOp.values) {
        expect(PendingOp.fromName(op.name), op);
      }
    });

    test('unknown or missing names mean no outstanding write', () {
      expect(PendingOp.fromName('nonsense'), PendingOp.none);
      expect(PendingOp.fromName(null), PendingOp.none);
    });
  });
}
