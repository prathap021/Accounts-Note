import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:accounts_note/core/constants/app_constants.dart';
import 'package:accounts_note/core/sync/sync_manager.dart';
import 'package:accounts_note/core/theme/app_theme.dart';
import 'package:accounts_note/data/local/transaction_local_store.dart';
import 'package:accounts_note/data/repositories/offline_transaction_repository.dart';
import 'package:accounts_note/data/repositories/transaction_repository.dart';
import 'package:accounts_note/features/reports/reports_screen.dart';
import 'package:accounts_note/models/transaction_model.dart';
import 'package:accounts_note/providers/auth_provider.dart';
import 'package:accounts_note/providers/settings_provider.dart';
import 'package:accounts_note/providers/sync_provider.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fixtures.dart';

/// Reports for any period: the presets, or days picked on the calendar,
/// including past history.
void main() {
  final now = DateTime.now();
  final lastYear = now.year - 1;

  group('ReportPeriod.resolve', () {
    final at = DateTime(2026, 11, 7, 15, 30);

    test('presets run from the start of the period to now', () {
      expect(
        const ReportPeriod(ReportRange.month).resolve(at),
        DateTimeRange(start: DateTime(2026, 11, 1), end: at),
      );
      expect(
        const ReportPeriod(ReportRange.year).resolve(at),
        DateTimeRange(start: DateTime(2026, 1, 1), end: at),
      );
      expect(
        const ReportPeriod(ReportRange.week).resolve(at).start,
        DateTime(2026, 11, 2),
        reason: 'Monday',
      );
    });

    test('a custom range covers its first and last days in full', () {
      final period = ReportPeriod(
        ReportRange.custom,
        custom: DateTimeRange(
          start: DateTime(2025, 3, 1),
          end: DateTime(2025, 3, 31),
        ),
      );
      final r = period.resolve(at);
      expect(r.start, DateTime(2025, 3, 1));
      expect(r.end, DateTime(2025, 3, 31, 23, 59, 59, 999));
    });
  });

  group('custom date range', () {
    late SharedPreferences prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
    });

    final ledger = [
      txFixture(
        id: 'march-pay',
        type: TransactionType.income,
        amount: 5000,
        categoryName: 'Salary',
        date: DateTime(lastYear, 3, 10, 9),
      ),
      txFixture(
        id: 'march-31',
        amount: 750,
        date: DateTime(lastYear, 3, 31, 21, 45),
      ),
      txFixture(id: 'april', amount: 999, date: DateTime(lastYear, 4, 1, 8)),
      txFixture(
        id: 'today',
        type: TransactionType.income,
        amount: 1200,
        categoryName: 'Salary',
        date: now.subtract(const Duration(minutes: 1)),
      ),
    ];

    Future<void> pumpReports(WidgetTester tester) async {
      tester.view.physicalSize = const Size(430, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final store = _MemoryStore(ledger);
      final remote = TransactionRepository(firestore: FakeFirebaseFirestore());
      final repo = OfflineTransactionRepository(
        store: store,
        remote: remote,
        syncManager: SyncManager(store: store, repository: remote),
        autoSync: false,
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            deviceCountryProvider.overrideWithValue('IN'),
            currentUidProvider.overrideWithValue(testUid),
            localStoreReadyProvider.overrideWith((ref) => true),
            offlineTransactionRepositoryProvider.overrideWithValue(repo),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const ReportsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    String pad(int n) => n.toString().padLeft(2, '0');
    String typed(DateTime d) => '${pad(d.month)}/${pad(d.day)}/${d.year}';

    /// Types the dates in the calendar's text mode and generates the report.
    Future<void> pickDates(
      WidgetTester tester,
      DateTime start,
      DateTime end,
    ) async {
      await tester.tap(find.byTooltip('Switch to input'));
      await tester.pumpAndSettle();
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), typed(start));
      await tester.enterText(fields.at(1), typed(end));
      await tester.tap(find.text('Generate'));
      await tester.pumpAndSettle();
    }

    testWidgets('offers Custom next to the presets', (tester) async {
      await pumpReports(tester);
      for (final label in ['Week', 'Month', 'Year', 'Custom']) {
        expect(
          find.descendant(
            of: find.byType(SegmentedButton<ReportRange>),
            matching: find.text(label),
          ),
          findsOneWidget,
        );
      }
      expect(find.text('This month so far'), findsOneWidget);
    });

    testWidgets('Custom opens the calendar, and cancel changes nothing', (
      tester,
    ) async {
      await pumpReports(tester);
      await tester.tap(find.text('Custom'));
      await tester.pumpAndSettle();
      expect(find.text('Select report period'), findsOneWidget);

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();

      expect(find.text('Select report period'), findsNothing);
      expect(find.text('This month so far'), findsOneWidget);
      expect(find.text('₹1,200.00'), findsWidgets);
    });

    testWidgets('a past period is reported on, both end days in full', (
      tester,
    ) async {
      await pumpReports(tester);
      await tester.tap(find.text('Custom'));
      await tester.pumpAndSettle();
      await pickDates(
        tester,
        DateTime(lastYear, 3, 1),
        DateTime(lastYear, 3, 31),
      );

      expect(find.text('Custom range'), findsOneWidget);
      expect(find.text('1 Mar $lastYear – 31 Mar $lastYear'), findsOneWidget);
      // In the totals and again in the category breakdown.
      expect(find.text('₹5,000.00'), findsWidgets, reason: 'income');
      expect(
        find.text('₹750.00'),
        findsWidgets,
        reason: '9:45 pm on the last day still counts',
      );
      expect(find.text('₹999.00'), findsNothing, reason: 'April is outside');
      expect(find.text('₹1,200.00'), findsNothing, reason: 'today is outside');
    });

    testWidgets('a period with nothing in it says so', (tester) async {
      await pumpReports(tester);
      await tester.tap(find.text('Custom'));
      await tester.pumpAndSettle();
      await pickDates(
        tester,
        DateTime(lastYear, 6, 1),
        DateTime(lastYear, 6, 30),
      );

      expect(find.text('Nothing in this period'), findsOneWidget);
    });

    testWidgets('tapping the dates reopens the calendar to change them', (
      tester,
    ) async {
      await pumpReports(tester);
      await tester.tap(find.byKey(const Key('report-period')));
      await tester.pumpAndSettle();
      await pickDates(
        tester,
        DateTime(lastYear, 4, 1),
        DateTime(lastYear, 4, 30),
      );
      expect(find.text('₹999.00'), findsWidgets);

      // Back to a preset, then Custom again: the calendar remembers.
      await tester.tap(find.text('Year'));
      await tester.pumpAndSettle();
      expect(find.text('This year so far'), findsOneWidget);
      await tester.tap(find.text('Custom'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Switch to input'));
      await tester.pumpAndSettle();
      expect(find.text(typed(DateTime(lastYear, 4, 1))), findsOneWidget);
    });

    testWidgets('export offers PDF, Excel and CSV for the period on screen', (
      tester,
    ) async {
      await pumpReports(tester);
      await tester.tap(find.byTooltip('Export report'));
      await tester.pumpAndSettle();

      expect(find.text('Export report'), findsOneWidget);
      expect(
        find.textContaining('1 transaction'),
        findsOneWidget,
        reason: "this month's entries",
      );
      expect(find.text('PDF document'), findsOneWidget);
      expect(find.text('Excel spreadsheet'), findsOneWidget);
      expect(find.text('CSV file'), findsOneWidget);
    });

    testWidgets('export with nothing in the period says so', (tester) async {
      await pumpReports(tester);
      await tester.tap(find.text('Custom'));
      await tester.pumpAndSettle();
      await pickDates(
        tester,
        DateTime(lastYear, 6, 1),
        DateTime(lastYear, 6, 30),
      );
      await tester.tap(find.byTooltip('Export report'));
      await tester.pumpAndSettle();

      expect(find.text('Nothing to export in this period.'), findsOneWidget);
      expect(find.text('PDF document'), findsNothing);
    });
  });
}

class _MemoryStore extends TransactionLocalStore {
  final List<TransactionModel> _items;

  _MemoryStore(Iterable<TransactionModel> items)
    : _items = [...items]..sort((a, b) => b.date.compareTo(a.date));

  @override
  List<TransactionModel> getAll() => _items;

  @override
  Stream<List<TransactionModel>> watch() => Stream.value(_items);
}
