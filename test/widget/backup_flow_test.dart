import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart' as cf;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:income_expense_tracker/core/sync/sync_manager.dart';
import 'package:income_expense_tracker/core/utils/result.dart';
import 'package:income_expense_tracker/data/local/transaction_local_store.dart';
import 'package:income_expense_tracker/data/repositories/backup_repository.dart';
import 'package:income_expense_tracker/data/repositories/transaction_repository.dart';
import 'package:income_expense_tracker/features/settings/backup_flow.dart';
import 'package:income_expense_tracker/providers/auth_provider.dart';
import 'package:income_expense_tracker/providers/settings_provider.dart';
import 'package:income_expense_tracker/providers/sync_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A backup file as the server writes it (the signature is the server's
/// business; the app only reads the payload for the preview).
String backupFile({int transactions = 3, String currency = 'INR'}) {
  Map<String, dynamic> tx(int i, String iso) => {
    'id': 't$i',
    'data': {
      'type': 'expense',
      'amount': 100 + i,
      'date': {'__ts': DateTime.parse(iso).millisecondsSinceEpoch},
    },
  };
  final payload = {
    'version': 1,
    'exportedAt': '2026-11-07T10:00:00.000Z',
    'sourceUid': 'asha',
    'sourceEmail': 'asha@example.com',
    'currency': currency,
    'collections': {
      'transactions': [
        for (var i = 0; i < transactions; i++)
          tx(i, i == 0 ? '2025-01-15T09:00:00' : '2026-10-0${i}T09:00:00'),
      ],
      'categories': [{}, {}],
      'creditCards': [{}],
      'budgets': <Object>[],
    },
  };
  return jsonEncode({
    'format': 'accounts-note-backup',
    'version': 1,
    'data': base64Encode(utf8.encode(jsonEncode(payload))),
    'signature': 'abc',
  });
}

class _FakeBackups extends BackupRepository {
  _FakeBackups() : super(functions: _NoFunctions());

  String? createdWith;
  String? imported;
  AppFailure? failImport;

  @override
  Future<Result<String>> create({required String currency}) async {
    createdWith = currency;
    return Result.success(backupFile());
  }

  @override
  Future<Result<ImportSummary>> importContent(String content) async {
    if (failImport != null) return Result.failure(failImport!);
    imported = content;
    return Result.success(
      const ImportSummary(
        transactionsAdded: 2,
        transactionsAlreadyThere: 1,
        categoriesAdded: 1,
        creditCardsAdded: 1,
        budgetsImported: 0,
      ),
    );
  }
}

class _NoFunctions implements cf.FirebaseFunctions {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('no functions in tests');
}

class _FakeFiles implements BackupFiles {
  String? toPick;
  String? sharedName;
  String? sharedContent;

  @override
  Future<String?> pick() async => toPick;

  @override
  Future<void> share(String fileName, String content) async {
    sharedName = fileName;
    sharedContent = content;
  }
}

class _Store extends TransactionLocalStore {
  _Store(this.pendingEntries);
  final int pendingEntries;

  @override
  int get pendingCount => pendingEntries;
}

class _Offline implements Connectivity {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => [
    ConnectivityResult.none,
  ];

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      const Stream.empty();
}

void main() {
  late SharedPreferences prefs;
  late _FakeBackups backups;
  late _FakeFiles files;

  setUp(() async {
    SharedPreferences.setMockInitialValues({'app_currency': 'USD'});
    prefs = await SharedPreferences.getInstance();
    backups = _FakeBackups();
    files = _FakeFiles();
  });

  Future<void> pump(WidgetTester tester, {int pending = 0}) async {
    final store = _Store(pending);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          backupRepositoryProvider.overrideWithValue(backups),
          backupFilesProvider.overrideWithValue(files),
          authStateProvider.overrideWith((ref) => Stream.value(null)),
          transactionLocalStoreProvider.overrideWithValue(store),
          syncManagerProvider.overrideWithValue(
            SyncManager(
              store: store,
              repository: TransactionRepository(
                firestore: FakeFirebaseFirestore(),
              ),
              connectivity: _Offline(),
            ),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => Column(
                children: [
                  TextButton(
                    onPressed: () => runBackup(context, ref),
                    child: const Text('backup'),
                  ),
                  TextButton(
                    onPressed: () => runImport(context, ref),
                    child: const Text('import'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  group('Back up now', () {
    testWidgets('makes the backup and hands it to the share sheet', (
      tester,
    ) async {
      await pump(tester);
      await tester.tap(find.text('backup'));
      await tester.pumpAndSettle();

      expect(backups.createdWith, 'USD');
      expect(
        files.sharedName,
        matches(RegExp(r'^accounts_note_backup_\d{4}-\d{2}-\d{2}\.json$')),
      );
      expect(files.sharedContent, backupFile());
      expect(find.text('Backup ready with 3 transactions.'), findsOneWidget);
    });

    testWidgets('warns when some entries have not synced yet', (tester) async {
      await pump(tester, pending: 2);
      await tester.tap(find.text('backup'));
      await tester.pumpAndSettle();

      expect(find.text('Some entries are not synced yet'), findsOneWidget);
      expect(
        find.textContaining("2 entries have not reached the cloud yet"),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(backups.createdWith, isNull);

      await tester.tap(find.text('backup'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Back up anyway'));
      await tester.pumpAndSettle();
      expect(files.sharedContent, isNotNull);
    });
  });

  group('Import a backup', () {
    testWidgets('previews the file, then imports it', (tester) async {
      files.toPick = backupFile();
      await pump(tester);
      await tester.tap(find.text('import'));
      await tester.pumpAndSettle();

      expect(find.text('Import this backup?'), findsOneWidget);
      expect(
        find.text('Made 7 Nov 2026 from asha@example.com.'),
        findsOneWidget,
      );
      expect(find.text('3 transactions'), findsOneWidget);
      expect(find.text('15 Jan 2025 – 2 Oct 2026'), findsOneWidget);
      expect(find.text('2 categories · 1 card · 0 budgets'), findsOneWidget);
      // The backup is in rupees, the app in dollars.
      expect(find.text('Switch the app to Indian Rupee (₹)'), findsOneWidget);

      await tester.tap(find.text('Import'));
      await tester.pumpAndSettle();

      expect(backups.imported, backupFile(), reason: 'sent unchanged');
      expect(prefs.getString('app_currency'), 'INR');
      expect(
        find.text('Imported 2 transactions (1 already here).'),
        findsOneWidget,
      );
    });

    testWidgets('the currency can be left as it is', (tester) async {
      files.toPick = backupFile();
      await pump(tester);
      await tester.tap(find.text('import'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      await tester.tap(find.text('Import'));
      await tester.pumpAndSettle();
      expect(prefs.getString('app_currency'), 'USD');
    });

    testWidgets('a file that is not a backup is refused before anything', (
      tester,
    ) async {
      files.toPick = '{"hello": "world"}';
      await pump(tester);
      await tester.tap(find.text('import'));
      await tester.pumpAndSettle();
      expect(
        find.text('That is not an Accounts Note backup file.'),
        findsOneWidget,
      );
      expect(backups.imported, isNull);
    });

    testWidgets("the server's refusal is shown", (tester) async {
      files.toPick = backupFile();
      backups.failImport = const AppFailure(
        'This backup file has been changed or damaged, so it cannot be '
        'imported.',
      );
      await pump(tester);
      await tester.tap(find.text('import'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Import'));
      await tester.pumpAndSettle();
      expect(find.textContaining('changed or damaged'), findsOneWidget);
      expect(prefs.getString('app_currency'), 'USD');
    });

    testWidgets('cancelling the file picker does nothing', (tester) async {
      files.toPick = null;
      await pump(tester);
      await tester.tap(find.text('import'));
      await tester.pumpAndSettle();
      expect(find.text('Import this backup?'), findsNothing);
    });
  });
}
