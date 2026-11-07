import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../core/constants/app_constants.dart';
import '../core/services/notifications.dart';
import '../core/utils/currency_formatter.dart';
import '../data/repositories/recurring_repository.dart';
import '../models/budget_model.dart';
import '../models/recurring_rule.dart';
import '../models/transaction_model.dart';
import 'auth_provider.dart';
import 'budget_provider.dart';
import 'period_provider.dart';
import 'settings_provider.dart';
import 'subscription_provider.dart';
import 'sync_provider.dart';

// ------------------------------------------------------------ notifications

@immutable
class NotificationSettings {
  final bool dailyReminder;

  /// Minutes after midnight.
  final int reminderMinutes;
  final bool budgetAlerts;
  final bool billReminders;

  const NotificationSettings({
    this.dailyReminder = false,
    this.reminderMinutes = 21 * 60,
    this.budgetAlerts = true,
    this.billReminders = true,
  });

  TimeOfDay get reminderTime =>
      TimeOfDay(hour: reminderMinutes ~/ 60, minute: reminderMinutes % 60);

  NotificationSettings copyWith({
    bool? dailyReminder,
    int? reminderMinutes,
    bool? budgetAlerts,
    bool? billReminders,
  }) => NotificationSettings(
    dailyReminder: dailyReminder ?? this.dailyReminder,
    reminderMinutes: reminderMinutes ?? this.reminderMinutes,
    budgetAlerts: budgetAlerts ?? this.budgetAlerts,
    billReminders: billReminders ?? this.billReminders,
  );
}

class NotificationSettingsNotifier extends Notifier<NotificationSettings> {
  static const _daily = 'notif_daily_reminder';
  static const _minutes = 'notif_reminder_minutes';
  static const _budgets = 'notif_budget_alerts';
  static const _bills = 'notif_bill_reminders';

  @override
  NotificationSettings build() {
    final p = ref.watch(sharedPreferencesProvider);
    return NotificationSettings(
      dailyReminder: p.getBool(_daily) ?? false,
      reminderMinutes: p.getInt(_minutes) ?? 21 * 60,
      budgetAlerts: p.getBool(_budgets) ?? true,
      billReminders: p.getBool(_bills) ?? true,
    );
  }

  AppNotifications get _notifications => ref.read(appNotificationsProvider);

  /// Turning it on asks for permission first. Returns whether it is on.
  Future<bool> setDailyReminder(bool on, {TimeOfDay? at}) async {
    final p = ref.read(sharedPreferencesProvider);
    if (on && !await _notifications.requestPermission()) return false;
    final minutes = at == null
        ? state.reminderMinutes
        : at.hour * 60 + at.minute;
    await p.setBool(_daily, on);
    await p.setInt(_minutes, minutes);
    state = state.copyWith(dailyReminder: on, reminderMinutes: minutes);
    if (on) {
      await _notifications.scheduleDailyReminder(state.reminderTime);
    } else {
      await _notifications.cancelDailyReminder();
    }
    return on;
  }

  Future<void> setBudgetAlerts(bool on) async {
    if (on) await _notifications.requestPermission();
    await ref.read(sharedPreferencesProvider).setBool(_budgets, on);
    state = state.copyWith(budgetAlerts: on);
  }

  Future<void> setBillReminders(bool on) async {
    if (on) await _notifications.requestPermission();
    await ref.read(sharedPreferencesProvider).setBool(_bills, on);
    state = state.copyWith(billReminders: on);
    await ref.read(recurringRunnerProvider).scheduleBillReminders();
  }

  /// After a restart or reinstall the OS may have dropped the schedule.
  Future<void> reapply() async {
    if (state.dailyReminder) {
      await _notifications.scheduleDailyReminder(state.reminderTime);
    }
  }
}

final notificationSettingsProvider =
    NotifierProvider<NotificationSettingsNotifier, NotificationSettings>(
      NotificationSettingsNotifier.new,
    );

// ---------------------------------------------------------------- recurring

final recurringRulesProvider = StreamProvider<List<RecurringRule>>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return Stream.value(const []);
  return ref.watch(recurringRepositoryProvider).watch(uid);
});

/// Makes the entries recurring rules owe, whenever the app opens or comes
/// back to the front. Background jobs are not relied on: phones stop them.
class RecurringRunner {
  RecurringRunner(this._ref);

  final Ref _ref;
  bool _running = false;

  /// Returns how many entries were added.
  Future<int> run({DateTime? now}) async {
    final uid = _ref.read(currentUidProvider);
    if (uid == null || _running) return 0;
    _running = true;
    var created = 0;
    try {
      final at = now ?? DateTime.now();
      final repo = _ref.read(recurringRepositoryProvider);
      final rules = await repo.fetchActive(uid);
      final transactions = _ref.read(offlineTransactionRepositoryProvider);
      final store = _ref.read(transactionLocalStoreProvider);

      outer:
      for (final rule in rules) {
        DateTime? last = rule.lastGenerated;
        for (final when in rule.dueOccurrences(at)) {
          final id = rule.entryIdFor(when);
          if (store.getById(id) == null) {
            // Automatic entries count like any other. A long catch-up that
            // would pass today's limit stops here and resumes tomorrow.
            final blocked = await _ref
                .read(dailyLimitCheckerProvider)
                .check(rule.type);
            if (blocked != null) {
              if (last != rule.lastGenerated) {
                await repo.save(uid, rule.copyWith(lastGenerated: last));
              }
              break outer;
            }
            final saved = await transactions.addTransaction(
              TransactionModel(
                id: id,
                type: rule.type,
                amount: rule.amount,
                categoryId: rule.categoryId,
                categoryName: rule.categoryName,
                note: rule.note,
                date: when,
                paymentMethod: rule.paymentMethod,
                creditCardId: rule.creditCardId,
                creditCardName: rule.creditCardName,
                accountId: rule.accountId,
                accountName: rule.accountName,
                isRecurring: true,
                recurringId: rule.id,
                createdAt: at,
                updatedAt: at,
              ),
            );
            if (!saved.isSuccess) break outer;
            created++;
          }
          last = when;
        }
        if (last != rule.lastGenerated) {
          await repo.save(uid, rule.copyWith(lastGenerated: last));
        }
      }
      await scheduleBillReminders(rules: rules);
    } catch (e) {
      debugPrint('Recurring entries could not be made: $e');
    } finally {
      _running = false;
    }
    return created;
  }

  /// A reminder at 9 am the day before each recurring expense is next due.
  Future<void> scheduleBillReminders({List<RecurringRule>? rules}) async {
    final notifications = _ref.read(appNotificationsProvider);
    final settings = _ref.read(notificationSettingsProvider);
    final uid = _ref.read(currentUidProvider);
    if (!settings.billReminders || uid == null) {
      await notifications.replaceBillReminders(const []);
      return;
    }
    final all =
        rules ?? await _ref.read(recurringRepositoryProvider).fetchActive(uid);
    final currency = _ref.read(settingsProvider).currency;
    final reminders = <BillReminder>[];
    for (final r in all) {
      if (r.type != TransactionType.expense) continue;
      final due = r.nextOccurrence();
      if (due == null) continue;
      final at = DateTime(due.year, due.month, due.day - 1, 9);
      reminders.add(
        BillReminder(
          id: r.id.hashCode & 0x7fffffff,
          at: at,
          title:
              '${r.note?.isNotEmpty == true ? r.note : r.categoryName} is due tomorrow',
          body:
              '${CurrencyFormatter.format(r.amount, currencyCode: currency)} '
              'will be added on ${DateFormat('d MMM').format(due)}.',
        ),
      );
    }
    await notifications.replaceBillReminders(reminders);
  }
}

final recurringRunnerProvider = Provider<RecurringRunner>((ref) {
  return RecurringRunner(ref);
});

// ------------------------------------------------------------ budget alerts

/// Alerts when spending crosses a budget's threshold (80% unless set
/// otherwise) and again at 100%, once each per budget per month.
class BudgetAlerts {
  BudgetAlerts(this._ref);

  final Ref _ref;

  static String _key(BudgetModel b, int percent) =>
      'budget_alert.${b.period}.${b.id}.$percent';

  Future<void> afterAdd(TransactionModel tx) async {
    if (tx.type != TransactionType.expense) return;
    if (!_ref.read(notificationSettingsProvider).budgetAlerts) return;
    final uid = _ref.read(currentUidProvider);
    if (uid == null) return;
    try {
      final month = _ref.read(currentMoneyMonthProvider);
      if (!month.contains(tx.date)) return;
      final budgets = await _ref
          .read(budgetRepositoryProvider)
          .watchBudgets(uid, month.key)
          .first
          .timeout(const Duration(seconds: 5));
      if (budgets.isEmpty) return;

      final repo = _ref.read(offlineTransactionRepositoryProvider);
      final byCategory = repo.categoryBreakdown(
        start: month.start,
        end: month.end,
      );
      final total = byCategory.values.fold<double>(0, (a, b) => a + b);
      final prefs = _ref.read(sharedPreferencesProvider);
      final currency = _ref.read(settingsProvider).currency;
      final notifications = _ref.read(appNotificationsProvider);

      for (final b in budgets) {
        if (b.limit <= 0) continue;
        // Spending is totalled by category name, as on the Budgets screen.
        final category = b.categoryName;
        if (b.categoryId != null &&
            b.categoryId != tx.categoryId &&
            category != tx.categoryName) {
          continue;
        }
        final spent = b.categoryId == null ? total : byCategory[category] ?? 0;
        final before = spent - tx.amount;
        for (final percent in {b.alertThresholdPercent.round(), 100}) {
          final line = b.limit * percent / 100;
          if (before < line && spent >= line) {
            if (prefs.getBool(_key(b, percent)) ?? false) continue;
            await prefs.setBool(_key(b, percent), true);
            final name = b.categoryName ?? 'Monthly';
            await notifications.showNow(
              id: 3000 + ((b.id.hashCode ^ percent) & 0x3ff),
              title: percent >= 100
                  ? '$name budget used up'
                  : '$name budget $percent% used',
              body:
                  '${CurrencyFormatter.format(spent, currencyCode: currency)} '
                  'of ${CurrencyFormatter.format(b.limit, currencyCode: currency)} '
                  'spent this month.',
              action: NotificationAction.openBudgets,
            );
          }
        }
      }
    } catch (e) {
      debugPrint('Budget alert check skipped: $e');
    }
  }
}

final budgetAlertsProvider = Provider<BudgetAlerts>((ref) {
  return BudgetAlerts(ref);
});
