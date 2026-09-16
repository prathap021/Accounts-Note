import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:income_expense_tracker/core/sync/sync_manager.dart';
import 'package:income_expense_tracker/core/theme/app_theme.dart';
import 'package:income_expense_tracker/providers/sync_provider.dart';
import 'package:income_expense_tracker/widgets/sync_status_chip.dart';

/// The chip is how a user finds out their data has not left the device, so
/// each state must be legible at a glance.
void main() {
  Future<void> pumpChip(WidgetTester tester, SyncState state,
      {Widget? child}) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ProviderScope(
      overrides: [currentSyncStateProvider.overrideWithValue(state)],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: child ?? const SyncStatusChip()),
      ),
    ));
    await tester.pump();
  }

  group('SyncStatusChip', () {
    testWidgets('reads Synced when everything is up to date', (tester) async {
      await pumpChip(tester, const SyncState(phase: SyncPhase.idle));
      expect(find.text('Synced'), findsOneWidget);
    });

    testWidgets('shows the queue length when work is pending', (tester) async {
      await pumpChip(
        tester,
        const SyncState(phase: SyncPhase.idle, pendingCount: 3),
      );
      expect(find.text('Pending · 3'), findsOneWidget);
    });

    testWidgets('shows a spinner while syncing', (tester) async {
      await pumpChip(tester, const SyncState(phase: SyncPhase.syncing));

      expect(find.text('Syncing'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('reads Offline with no queue', (tester) async {
      await pumpChip(
        tester,
        const SyncState(phase: SyncPhase.offline, isOnline: false),
      );
      expect(find.text('Offline'), findsOneWidget);
    });

    testWidgets('reads Failed and counts the failures', (tester) async {
      await pumpChip(
        tester,
        const SyncState(phase: SyncPhase.failed, failedCount: 2),
      );
      expect(find.text('Failed · 2'), findsOneWidget);
    });
  });

  group('SyncFailureBanner', () {
    testWidgets('stays out of the way when nothing has failed',
        (tester) async {
      await pumpChip(
        tester,
        const SyncState(phase: SyncPhase.idle),
        child: const SyncFailureBanner(),
      );

      expect(find.text('Retry'), findsNothing);
    });

    testWidgets('explains the failure and offers a retry', (tester) async {
      await pumpChip(
        tester,
        const SyncState(phase: SyncPhase.failed, failedCount: 1),
        child: const SyncFailureBanner(),
      );

      expect(find.textContaining('saved on this device'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('pluralises the count', (tester) async {
      await pumpChip(
        tester,
        const SyncState(phase: SyncPhase.failed, failedCount: 3),
        child: const SyncFailureBanner(),
      );

      expect(find.textContaining('3 entries'), findsOneWidget);
    });
  });
}
