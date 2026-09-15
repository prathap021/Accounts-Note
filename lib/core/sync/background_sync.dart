import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../../data/local/transaction_local_store.dart';
import '../../data/repositories/transaction_repository.dart';
import '../../firebase_options.dart';
import 'sync_manager.dart';

/// Entry point for the background isolate.
///
/// This runs with no access to the app's widget tree or Riverpod graph, so it
/// rebuilds the minimum it needs — Firebase, Hive, the local store — and then
/// drives exactly the same [SyncManager] the foreground uses.
@pragma('vm:entry-point')
void backgroundSyncDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    return BackgroundSync.runIsolatedSync(taskName);
  });
}

/// Schedules and executes sync while the app is backgrounded or closed.
///
/// Android: WorkManager, which survives the app being swept away and reboots.
/// iOS: BGTaskScheduler, which the system runs opportunistically — iOS gives
/// no guarantee about when, so this is a best-effort catch-up, not a timer.
class BackgroundSync {
  /// Android WorkManager unique names.
  static const periodicUniqueName = 'accounts-note-sync-periodic';
  static const oneOffUniqueName = 'accounts-note-sync-oneoff';

  /// Task identifiers. On iOS these MUST match the entries in
  /// `BGTaskSchedulerPermittedIdentifiers` in Info.plist and the
  /// registrations in AppDelegate.swift.
  static const refreshTaskId = 'com.accountsnote.sync.refresh';
  static const processingTaskId = 'com.accountsnote.sync.processing';

  /// Set while the app is in the foreground. The background isolate uses it to
  /// stand down: two isolates must not hold the same Hive box open.
  static const _foregroundKey = 'app_in_foreground';

  static Future<void> initialize() async {
    if (kIsWeb) return;
    await Workmanager().initialize(backgroundSyncDispatcher);
  }

  /// Records whether the UI is currently running, so the background isolate
  /// can skip work the foreground is already doing.
  static Future<void> setAppInForeground(bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_foregroundKey, value);
    } catch (_) {
      // A missing flag only costs us a skipped background run.
    }
  }

  /// Periodic catch-up. Android's floor is 15 minutes; iOS decides for itself.
  static Future<void> registerPeriodic() async {
    if (kIsWeb) return;
    try {
      await Workmanager().registerPeriodicTask(
        periodicUniqueName,
        refreshTaskId,
        frequency: const Duration(minutes: 15),
        // `update` so changing the schedule in a later build actually takes
        // effect instead of silently keeping the old frequency.
        existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
        constraints: Constraints(
          networkType: NetworkType.connected,
          requiresBatteryNotLow: true,
        ),
        backoffPolicy: BackoffPolicy.exponential,
        backoffPolicyDelay: const Duration(minutes: 1),
      );
    } catch (e) {
      debugPrint('Could not register periodic sync: $e');
    }
  }

  /// Queues a one-off attempt that the OS runs as soon as there is a network.
  ///
  /// Called when a write is made with no connectivity, so the entry still
  /// reaches the cloud even if the user never reopens the app.
  static Future<void> scheduleWhenOnline() async {
    if (kIsWeb) return;
    try {
      await Workmanager().registerOneOffTask(
        oneOffUniqueName,
        processingTaskId,
        existingWorkPolicy: ExistingWorkPolicy.replace,
        constraints: Constraints(networkType: NetworkType.connected),
        backoffPolicy: BackoffPolicy.exponential,
        backoffPolicyDelay: const Duration(minutes: 1),
      );
    } catch (e) {
      debugPrint('Could not schedule catch-up sync: $e');
    }
  }

  static Future<void> cancelAll() async {
    if (kIsWeb) return;
    try {
      await Workmanager().cancelAll();
    } catch (e) {
      debugPrint('Could not cancel background sync: $e');
    }
  }

  /// The actual background work. Returns false to ask the platform to retry.
  static Future<bool> runIsolatedSync(String taskName) async {
    WidgetsFlutterBinding.ensureInitialized();

    try {
      // Stand down if the UI is live — it syncs on its own, and a second
      // isolate opening the same Hive box risks corrupting it.
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_foregroundKey) ?? false) return true;
    } catch (_) {
      // Fall through: better to attempt the sync than to skip silently.
    }

    TransactionLocalStore? store;
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      }

      final uid = await _resolveUid();
      // Signed out: nothing to sync, and retrying will not change that.
      if (uid == null) return true;

      await Hive.initFlutter();
      store = TransactionLocalStore();
      await store.open(uid);

      if (store.pendingCount == 0 && store.failedCount == 0) return true;

      final manager = SyncManager(
        store: store,
        repository: TransactionRepository(),
      );
      await manager.syncNow();
      await manager.dispose();

      // Anything still queued means the platform should try again later.
      return store.pendingCount == 0 && store.failedCount == 0;
    } catch (e, st) {
      debugPrint('Background sync ($taskName) failed: $e\n$st');
      return false;
    } finally {
      await store?.close();
    }
  }

  /// Firebase restores the session asynchronously in a fresh isolate, so give
  /// it a moment rather than concluding the user is signed out.
  static Future<String?> _resolveUid() async {
    final immediate = FirebaseAuth.instance.currentUser?.uid;
    if (immediate != null) return immediate;
    try {
      final user = await FirebaseAuth.instance
          .authStateChanges()
          .firstWhere((u) => u != null)
          .timeout(const Duration(seconds: 8));
      return user?.uid;
    } catch (_) {
      return null;
    }
  }
}
