import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:accounts_note/core/constants/app_constants.dart';
import 'package:accounts_note/core/services/notifications.dart';
import 'package:accounts_note/core/sync/sync_manager.dart';
import 'package:accounts_note/data/repositories/budget_repository.dart';
import 'package:accounts_note/data/repositories/offline_transaction_repository.dart';
import 'package:accounts_note/data/repositories/profile_repository.dart';
import 'package:accounts_note/data/repositories/recurring_repository.dart';
import 'package:accounts_note/data/repositories/transaction_repository.dart';
import 'package:accounts_note/models/budget_model.dart';
import 'package:accounts_note/models/daily_usage.dart';
import 'package:accounts_note/models/recurring_rule.dart';
import 'package:accounts_note/providers/auth_provider.dart';
import 'package:accounts_note/providers/automation_provider.dart';
import 'package:accounts_note/providers/budget_provider.dart';
import 'package:accounts_note/providers/profile_provider.dart';
import 'package:accounts_note/providers/settings_provider.dart';
import 'package:accounts_note/providers/sync_provider.dart';
import 'package:accounts_note/providers/transaction_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_notifications.dart';
import '../support/fixtures.dart';

RecurringRule rule({
  RecurrenceFrequency frequency = RecurrenceFrequency.monthly,
  required DateTime start,
  DateTime? end,
  DateTime? last,
  String id = 'r1',
  TransactionType type = TransactionType.expense,
}) => RecurringRule(
  id: id,
  type: type,
  amount: 15000,
  categoryId: 'rent',
  categoryName: 'Rent',
  note: 'Flat rent',
  paymentMethod: 'UPI',
  frequency: frequency,
  startDate: start,
  endDate: end,
  lastGenerated: last,
  createdAt: start,
);

class _Online implements Connectivity {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => [
    ConnectivityResult.wifi,
  ];

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      const Stream.empty();
}

void main() {
  group('when a rule falls due', () {
    test('monthly on the 31st uses the last day of shorter months', () {
      final r = rule(start: DateTime(2026, 1, 31, 9));
      expect(
        [for (var n = 0; n < 5; n++) r.occurrence(n)],
        [
          DateTime(2026, 1, 31, 9),
          DateTime(2026, 2, 28, 9),
          DateTime(2026, 3, 31, 9),
          DateTime(2026, 4, 30, 9),
          DateTime(2026, 5, 31, 9),
        ],
      );
      expect(
        rule(start: DateTime(2028, 1, 31)).occurrence(1),
        DateTime(2028, 2, 29),
        reason: 'leap year',
      );
    });

    test('yearly on 29 February falls on the 28th in other years', () {
      final r = rule(
        frequency: RecurrenceFrequency.yearly,
        start: DateTime(2028, 2, 29),
      );
      expect(r.occurrence(1), DateTime(2029, 2, 28));
      expect(r.occurrence(4), DateTime(2032, 2, 29));
    });

    test('weekly and daily step by calendar days', () {
      final w = rule(
        frequency: RecurrenceFrequency.weekly,
        start: DateTime(2026, 10, 30, 8),
      );
      expect(w.occurrence(1), DateTime(2026, 11, 6, 8));
      final d = rule(
        frequency: RecurrenceFrequency.daily,
        start: DateTime(2026, 12, 31, 20),
      );
      expect(d.occurrence(1), DateTime(2027, 1, 1, 20));
    });

    test('only occurrences after the last entry and up to now are due', () {
      final r = rule(
        start: DateTime(2026, 8, 5, 9),
        last: DateTime(2026, 8, 5, 9),
      );
      expect(r.dueOccurrences(DateTime(2026, 11, 7)), [
        DateTime(2026, 9, 5, 9),
        DateTime(2026, 10, 5, 9),
        DateTime(2026, 11, 5, 9),
      ]);
      expect(r.nextOccurrence(), DateTime(2026, 9, 5, 9));
    });

    test('an end date stops it, and a paused rule is never due', () {
      final ended = rule(
        start: DateTime(2026, 8, 5),
        end: DateTime(2026, 9, 30),
      );
      expect(ended.dueOccurrences(DateTime(2026, 11, 7)), [
        DateTime(2026, 8, 5),
        DateTime(2026, 9, 5),
      ]);
      final paused = rule(start: DateTime(2026, 8, 5)).copyWith(active: false);
      expect(paused.dueOccurrences(DateTime(2026, 11, 7)), isEmpty);
    });

    test('each occurrence has its own fixed entry id', () {
      final r = rule(start: DateTime(2026, 8, 5));
      expect(r.entryIdFor(DateTime(2026, 9, 5)), 'rec-r1-20260905');
    });
  });

  group('making the entries', () {
    final hive = HiveHarness();
    late FakeFirebaseFirestore firestore;
    late FakeNotifications notifications;
    late ProviderContainer container;

    setUp(() async {
      await hive.setUp();
      firestore = FakeFirebaseFirestore();
      await firestore.doc(FirestorePaths.user(testUid)).set({'email': 'a@b.c'});
      notifications = FakeNotifications();
      SharedPreferences.setMockInitialValues({'app_has_seen_onboarding': true});
      final prefs = await SharedPreferences.getInstance();
      final remote = TransactionRepository(firestore: firestore);
      container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          currentUidProvider.overrideWithValue(testUid),
          transactionRepositoryProvider.overrideWithValue(remote),
          profileRepositoryProvider.overrideWithValue(
            ProfileRepository(firestore: firestore),
          ),
          recurringRepositoryProvider.overrideWithValue(
            RecurringRepository(firestore: firestore),
          ),
          budgetRepositoryProvider.overrideWithValue(
            BudgetRepository(firestore: firestore),
          ),
          appNotificationsProvider.overrideWithValue(notifications),
          transactionLocalStoreProvider.overrideWithValue(hive.store),
          offlineTransactionRepositoryProvider.overrideWith(
            (ref) => OfflineTransactionRepository(
              usageStore: ref.watch(dailyUsageStoreProvider),
              store: hive.store,
              remote: remote,
              syncManager: SyncManager(
                store: hive.store,
                repository: remote,
                connectivity: _Online(),
              ),
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

    Future<void> saveRule(RecurringRule r) =>
        container.read(recurringRepositoryProvider).save(testUid, r);

    Future<RecurringRule> storedRule(String id) async => RecurringRule.fromDoc(
      await firestore.doc('${FirestorePaths.recurring(testUid)}/$id').get(),
    );

    test('catches up every missed occurrence, once', () async {
      final now = DateTime.now();
      final start = DateTime(now.year, now.month - 2, 1, 9);
      await saveRule(rule(start: start, last: start));

      final runner = container.read(recurringRunnerProvider);
      expect(await runner.run(now: now), 2);
      final made = hive.store.getAll().where((t) => t.isRecurring).toList();
      expect(made, hasLength(2));
      expect(made.every((t) => t.recurringId == 'r1'), isTrue);
      expect(made.first.categoryName, 'Rent');

      expect(await runner.run(now: now), 0, reason: 'nothing is due twice');
      expect((await storedRule('r1')).lastGenerated, made.first.date);
    });

    test('an entry already made on another device is not made again', () async {
      final now = DateTime.now();
      final start = DateTime(now.year, now.month - 1, 1, 9);
      final r = rule(start: start, last: start);
      await saveRule(r);
      final due = r.dueOccurrences(now).single;
      await hive.store.put(
        txFixture(id: r.entryIdFor(due), date: due, categoryName: 'Rent'),
      );

      expect(await container.read(recurringRunnerProvider).run(now: now), 0);
      expect((await storedRule('r1')).lastGenerated, due);
    });

    test(
      'a long catch-up stops at the daily limit and resumes later',
      () async {
        final now = DateTime.now();
        await firestore
            .doc(FirestorePaths.usageDay(testUid, todayKey(now)))
            .set({'income': 0, 'expense': 12, 'lastTxId': 'x'});
        final start = DateTime(now.year, now.month, now.day - 10, 7);
        await saveRule(
          rule(frequency: RecurrenceFrequency.daily, start: start, last: start),
        );

        final made = await container
            .read(recurringRunnerProvider)
            .run(now: now);
        expect(made, 2, reason: '14 a day on Free, 12 already used');
        final last = (await storedRule('r1')).lastGenerated!;
        expect(last.isBefore(now), isTrue);
        expect(last.day, start.add(const Duration(days: 2)).day);
      },
    );

    test(
      'a recurring expense gets a reminder the day before it is due',
      () async {
        final now = DateTime.now();
        final start = DateTime(now.year, now.month, now.day, 9);
        await saveRule(rule(start: start, last: start));

        await container.read(recurringRunnerProvider).run(now: now);

        final reminder = notifications.bills.single;
        final due = rule(start: start, last: start).nextOccurrence()!;
        expect(reminder.at, DateTime(due.year, due.month, due.day - 1, 9));
        expect(reminder.title, 'Flat rent is due tomorrow');
      },
    );
  });

  group('budget alerts', () {
    final hive = HiveHarness();
    late FakeFirebaseFirestore firestore;
    late FakeNotifications notifications;
    late ProviderContainer container;

    setUp(() async {
      await hive.setUp();
      firestore = FakeFirebaseFirestore();
      notifications = FakeNotifications();
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final remote = TransactionRepository(firestore: firestore);
      container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          currentUidProvider.overrideWithValue(testUid),
          budgetRepositoryProvider.overrideWithValue(
            BudgetRepository(firestore: firestore),
          ),
          appNotificationsProvider.overrideWithValue(notifications),
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
      final period = container.read(currentPeriodProvider);
      await BudgetRepository(firestore: firestore).setBudget(
        testUid,
        BudgetModel(
          id: '',
          period: period,
          categoryId: 'cat-food',
          categoryName: 'Food',
          limit: 1000,
          alertThresholdPercent: 80,
          createdAt: DateTime.now(),
        ),
      );
    });

    tearDown(() async {
      container.dispose();
      await hive.tearDown();
    });

    Future<void> spend(String id, double amount) async {
      final tx = txFixture(id: id, amount: amount, date: DateTime.now());
      await hive.store.put(tx);
      await container.read(budgetAlertsProvider).afterAdd(tx);
    }

    test('alerts at 80% and at 100%, once each', () async {
      await spend('a', 500);
      expect(notifications.shown, isEmpty);
      await spend('b', 350); // 850: past 80%
      expect(notifications.shown.single.title, 'Food budget 80% used');
      await spend('c', 50); // 900: no new line crossed
      expect(notifications.shown, hasLength(1));
      await spend('d', 150); // 1050: past 100%
      expect(notifications.shown.last.title, 'Food budget used up');
      expect(notifications.shown.last.action, NotificationAction.openBudgets);
      await spend('e', 10);
      expect(notifications.shown, hasLength(2));
    });

    test('can be turned off', () async {
      await container
          .read(notificationSettingsProvider.notifier)
          .setBudgetAlerts(false);
      await spend('a', 2000);
      expect(notifications.shown, isEmpty);
    });
  });

  group('daily reminder', () {
    test('is scheduled at the chosen time, and only with permission', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final notifications = FakeNotifications();
      final c = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          appNotificationsProvider.overrideWithValue(notifications),
        ],
      );
      addTearDown(c.dispose);
      final n = c.read(notificationSettingsProvider.notifier);

      expect(
        await n.setDailyReminder(
          true,
          at: const TimeOfDay(hour: 20, minute: 30),
        ),
        isTrue,
      );
      expect(notifications.dailyAt, const TimeOfDay(hour: 20, minute: 30));
      await n.setDailyReminder(false);
      expect(notifications.dailyAt, isNull);

      notifications.permission = false;
      expect(await n.setDailyReminder(true), isFalse);
      expect(c.read(notificationSettingsProvider).dailyReminder, isFalse);
    });
  });
}
