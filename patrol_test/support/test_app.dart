import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:income_expense_tracker/core/constants/app_constants.dart';
import 'package:income_expense_tracker/core/services/avatar_cache.dart';
import 'package:income_expense_tracker/core/sync/sync_manager.dart';
import 'package:income_expense_tracker/data/repositories/account_repository.dart';
import 'package:income_expense_tracker/data/repositories/auth_repository.dart';
import 'package:income_expense_tracker/data/repositories/csv_import_repository.dart';
import 'package:income_expense_tracker/data/repositories/receipt_repository.dart';
import 'package:income_expense_tracker/data/repositories/backup_repository.dart';
import 'package:income_expense_tracker/data/repositories/budget_repository.dart';
import 'package:income_expense_tracker/data/repositories/data_reset_repository.dart';
import 'package:income_expense_tracker/data/repositories/recurring_repository.dart';
import 'package:income_expense_tracker/core/services/notifications.dart';
import 'package:income_expense_tracker/data/repositories/category_repository.dart';
import 'package:income_expense_tracker/data/repositories/profile_repository.dart';
import 'package:income_expense_tracker/data/repositories/credit_card_repository.dart';
import 'package:income_expense_tracker/data/repositories/transaction_repository.dart';
import 'package:income_expense_tracker/main.dart';
import 'package:income_expense_tracker/models/transaction_model.dart';
import 'package:income_expense_tracker/providers/account_provider.dart';
import 'package:income_expense_tracker/providers/app_lock_provider.dart';
import 'package:income_expense_tracker/providers/auth_provider.dart';
import 'package:income_expense_tracker/providers/budget_provider.dart';
import 'package:income_expense_tracker/providers/category_provider.dart';
import 'package:income_expense_tracker/providers/profile_provider.dart';
import 'package:income_expense_tracker/providers/credit_card_provider.dart';
import 'package:income_expense_tracker/providers/settings_provider.dart';
import 'package:income_expense_tracker/providers/subscription_provider.dart';
import 'package:income_expense_tracker/providers/sync_provider.dart';
import 'package:income_expense_tracker/providers/transaction_provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:patrol/patrol.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_backend.dart';

export 'fake_backend.dart';

const testPassword = 'correct-horse';

bool _deviceStorageReady = false;

/// Boots the real app — real screens, router, Hive and preferences — with
/// every network dependency swapped for [backend].
///
/// Mirrors `main()` minus the parts that must not run under test: Firebase
/// initialisation (nothing may reach the production project), Crashlytics,
/// Analytics and the WorkManager background isolate.
Future<FakeBackend> launchApp(
  PatrolIntegrationTester $, {
  FakeBackend? backend,
  bool hasSeenOnboarding = true,
}) async {
  backend ??= FakeBackend();

  if (!_deviceStorageReady) {
    await Hive.initFlutter();
    await AvatarCache.instance.init();
    _deviceStorageReady = true;
  }

  // Every test runs in the same app session, one after another, so each one
  // starts by putting the device back to a fresh install: no ledger and no
  // preferences left behind by the test before it.
  await _wipeDeviceStorage($);
  final prefs = await SharedPreferences.getInstance();
  await prefs.clear();
  if (hasSeenOnboarding) {
    await prefs.setBool('app_has_seen_onboarding', true);
  }

  await _pumpApp($, backend, prefs);
  return backend;
}

/// Opens the app as a returning, verified user whose session is still
/// active. [seed] runs against the backend before the first frame, for cloud
/// data that should already exist when the app starts.
Future<(FakeBackend, FakeAccount)> launchSignedIn(
  PatrolIntegrationTester $, {
  Future<void> Function(FakeBackend backend, FakeAccount user)? seed,
}) async {
  final backend = FakeBackend();
  final user = await backend.seedUser();
  await seed?.call(backend, user);
  await launchApp($, backend: backend);
  await waitForScreen($, 'AVAILABLE BALANCE');
  return (backend, user);
}

/// Waits for [text], and on timeout fails with what the screen showed
/// instead, so a stuck flow explains itself in the test report.
Future<void> waitForScreen(
  PatrolIntegrationTester $,
  String text, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  try {
    await $(text).waitUntilVisible(timeout: timeout);
  } on Object catch (_) {
    throw TestFailure(
      'Expected "$text" but the screen showed:\n${describeScreen($)}',
    );
  }
}

/// Every piece of text currently on screen, plus any pending framework error.
String describeScreen(PatrolIntegrationTester $) {
  final texts = $.tester
      .widgetList<Text>(find.byType(Text))
      .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '')
      .where((t) => t.trim().isNotEmpty)
      .toList();
  final error = $.tester.takeException();
  return ['texts: $texts', if (error != null) 'error: $error'].join('\n');
}

/// Closes the app and opens it again against the same backend and device
/// storage — a cold start, as after the user swipes the app away.
Future<void> restartApp(PatrolIntegrationTester $, FakeBackend backend) async {
  // Unmounting the scope disposes every provider, which closes the Hive box
  // exactly as process death would leave it.
  await $.pumpWidget(const SizedBox.shrink());
  await $.pump(const Duration(milliseconds: 300));
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  await _pumpApp($, backend, prefs);
}

/// Removes every Hive box the app has written, as uninstalling would.
///
/// The previous test's app is unmounted first so its providers close their
/// boxes; a box still open is closed and deleted by [Hive.deleteBoxFromDisk].
Future<void> _wipeDeviceStorage(PatrolIntegrationTester $) async {
  await $.pumpWidget(const SizedBox.shrink());
  await $.pump(const Duration(milliseconds: 100));
  final dir = await getApplicationDocumentsDirectory();
  for (final file in dir.listSync().whereType<File>()) {
    final name = file.uri.pathSegments.last;
    if (name.endsWith('.hive')) {
      await Hive.deleteBoxFromDisk(name.substring(0, name.length - 5));
    }
  }
}

Future<void> _pumpApp(
  PatrolIntegrationTester $,
  FakeBackend backend,
  SharedPreferences prefs,
) async {
  await $.pumpWidget(
    ProviderScope(
      overrides: appOverrides(backend, prefs),
      child: const IncomeExpenseTrackerApp(),
    ),
  );
  await $.pumpAndTrySettle();
}

List<Override> appOverrides(FakeBackend backend, SharedPreferences prefs) {
  final firestore = backend.firestore;
  return [
    sharedPreferencesProvider.overrideWithValue(prefs),
    authRepositoryProvider.overrideWithValue(
      AuthRepository(
        auth: backend.auth,
        firestore: firestore,
      ),
    ),
    transactionRepositoryProvider.overrideWithValue(
      TransactionRepository(firestore: firestore),
    ),
    categoryRepositoryProvider.overrideWithValue(
      CategoryRepository(firestore: firestore),
    ),
    budgetRepositoryProvider.overrideWithValue(
      BudgetRepository(firestore: firestore),
    ),
    creditCardRepositoryProvider.overrideWithValue(
      CreditCardRepository(firestore: firestore),
    ),
    accountRepositoryProvider.overrideWithValue(
      AccountRepository(firestore: firestore),
    ),
    profileRepositoryProvider.overrideWithValue(
      ProfileRepository(firestore: firestore),
    ),
    subscriptionStoreProvider.overrideWithValue(backend.store),
    backupRepositoryProvider.overrideWithValue(backend.backups),
    appNotificationsProvider.overrideWithValue(backend.notifications),
    biometricUnlockProvider.overrideWithValue(backend.biometrics),
    receiptPickerProvider.overrideWithValue(backend.receiptPicker),
    receiptRepositoryProvider.overrideWithValue(
      ReceiptRepository(firestore: firestore),
    ),
    csvImportServiceProvider.overrideWithValue(backend.csvImport),
    recurringRepositoryProvider.overrideWithValue(
      RecurringRepository(firestore: firestore),
    ),
    dataResetRepositoryProvider.overrideWithValue(
      DataResetRepository(firestore: firestore),
    ),
    backupFilesProvider.overrideWithValue(backend.backupFiles),
    subscriptionRepositoryProvider.overrideWithValue(backend.subscriptions),
    // Same wiring as production, with connectivity under the test's control.
    syncManagerProvider.overrideWith((ref) {
      final manager = SyncManager(
        store: ref.watch(transactionLocalStoreProvider),
        repository: ref.watch(transactionRepositoryProvider),
        connectivity: backend.connectivity,
        usageStore: ref.watch(dailyUsageStoreProvider),
      );
      ref.onDispose(manager.dispose);
      return manager;
    }),
  ];
}

/// Server-side state for an existing user, written the way the app writes it.
extension Seeding on FakeBackend {
  /// An account that signed up before, with its profile and the default
  /// categories the app seeds on first sign-in.
  ///
  /// [signedIn] leaves the session active, as after a previous launch.
  Future<FakeAccount> seedUser({
    String email = 'asha@example.com',
    String password = testPassword,
    String? displayName = 'Asha Rao',
    bool emailVerified = true,
    bool signedIn = true,
  }) async {
    final account = auth.register(
      email: email,
      password: password,
      displayName: displayName,
      emailVerified: emailVerified,
    );
    // Signing in through the real repository creates users/{uid} and the
    // default categories exactly as the app does on a first sign-in.
    final repo = AuthRepository(
      auth: auth,
      firestore: firestore,
    );
    final result = await repo.signInWithEmail(email, password);
    if (!result.isSuccess) {
      throw StateError('Could not seed $email');
    }
    if (displayName != null) {
      await firestore
          .collection(FirestoreCollections.users)
          .doc(account.uid)
          .set({'displayName': displayName}, SetOptions(merge: true));
    }
    if (!signedIn) await auth.signOut();
    return account;
  }

  /// The id of a seeded category, so a cloud transaction can point at it.
  Future<String> categoryId(
    String uid,
    String name, {
    TransactionType type = TransactionType.expense,
  }) async {
    final snap = await firestore
        .collection(FirestorePaths.categories(uid))
        .where('name', isEqualTo: name)
        .where('type', isEqualTo: type.name)
        .get();
    return snap.docs.single.id;
  }

  /// Writes a transaction to the cloud, as if logged on another device. The
  /// app pulls it down on its next sync.
  Future<TransactionModel> seedTransaction(
    String uid, {
    required String id,
    required double amount,
    required String category,
    TransactionType type = TransactionType.expense,
    String? note,
    DateTime? date,
  }) async {
    final when = date ?? DateTime.now().subtract(const Duration(minutes: 5));
    final tx = TransactionModel(
      id: id,
      type: type,
      amount: amount,
      categoryId: await categoryId(uid, category, type: type),
      categoryName: category,
      note: note,
      date: when,
      paymentMethod: 'Cash',
      createdAt: when,
      updatedAt: when,
    );
    await firestore
        .collection(FirestorePaths.transactions(uid))
        .doc(id)
        .set(tx.toMap());
    return tx;
  }

  /// Transactions currently in the cloud for [uid].
  Future<List<TransactionModel>> cloudTransactions(String uid) async {
    final snap = await firestore
        .collection(FirestorePaths.transactions(uid))
        .get();
    return snap.docs.map(TransactionModel.fromDoc).toList();
  }
}
