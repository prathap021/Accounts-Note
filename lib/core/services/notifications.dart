import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// What a notification opens when tapped.
abstract final class NotificationAction {
  static const addExpense = 'add_expense';
  static const openBudgets = 'open_budgets';
}

/// Local notifications: the daily "add your expenses" reminder, bill
/// reminders for recurring expenses, and budget alerts. An interface, so
/// tests can record what would be shown.
abstract class AppNotifications {
  Future<void> init();

  /// Asks the user (Android 13+, iOS). True if allowed.
  Future<bool> requestPermission();

  Future<void> scheduleDailyReminder(TimeOfDay at);
  Future<void> cancelDailyReminder();

  /// Replaces every bill reminder with these (id → when, title, body).
  Future<void> replaceBillReminders(List<BillReminder> reminders);

  Future<void> showNow({
    required int id,
    required String title,
    required String body,
    String? action,
  });

  /// Taps on notifications, as their [NotificationAction].
  Stream<String> get taps;

  /// The action of the notification the app was opened from, if any.
  Future<String?> launchAction();
}

class BillReminder {
  final int id;
  final DateTime at;
  final String title;
  final String body;

  const BillReminder({
    required this.id,
    required this.at,
    required this.title,
    required this.body,
  });
}

class LocalNotifications implements AppNotifications {
  LocalNotifications([FlutterLocalNotificationsPlugin? plugin])
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  final _taps = StreamController<String>.broadcast();
  bool _ready = false;

  static const dailyReminderId = 1000;

  /// Bill reminders use ids 2000–2999.
  static const _billIdBase = 2000;

  static const _reminders = AndroidNotificationDetails(
    'reminders',
    'Reminders',
    channelDescription: 'Daily reminder and bills due',
    importance: Importance.defaultImportance,
  );
  static const _alerts = AndroidNotificationDetails(
    'budget_alerts',
    'Budget alerts',
    channelDescription: 'When spending reaches a budget',
    importance: Importance.high,
    priority: Priority.high,
  );

  @override
  Future<void> init() async {
    if (_ready) return;
    try {
      tzdata.initializeTimeZones();
      try {
        final local = await FlutterTimezone.getLocalTimezone();
        tz.setLocalLocation(tz.getLocation(local.identifier));
      } catch (e) {
        debugPrint('Local time zone unknown, using UTC: $e');
      }
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
        onDidReceiveNotificationResponse: (r) {
          final p = r.payload;
          if (p != null) _taps.add(p);
        },
      );
      _ready = true;
    } catch (e) {
      debugPrint('Notifications unavailable: $e');
    }
  }

  @override
  Future<bool> requestPermission() async {
    await init();
    try {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      if (android != null) {
        return await android.requestNotificationsPermission() ?? true;
      }
      final ios = _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      if (ios != null) {
        return await ios.requestPermissions(
              alert: true,
              badge: true,
              sound: true,
            ) ??
            false;
      }
    } catch (e) {
      debugPrint('Notification permission request failed: $e');
    }
    return false;
  }

  tz.TZDateTime _nextAt(TimeOfDay at) {
    final now = tz.TZDateTime.now(tz.local);
    var t = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      at.hour,
      at.minute,
    );
    if (!t.isAfter(now)) t = t.add(const Duration(days: 1));
    return t;
  }

  @override
  Future<void> scheduleDailyReminder(TimeOfDay at) async {
    await init();
    try {
      await _plugin.zonedSchedule(
        id: dailyReminderId,
        title: 'Add your expenses',
        body: 'Note down what you spent today, while you remember it.',
        scheduledDate: _nextAt(at),
        notificationDetails: const NotificationDetails(
          android: _reminders,
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
        payload: NotificationAction.addExpense,
      );
    } catch (e) {
      debugPrint('Could not schedule the daily reminder: $e');
    }
  }

  @override
  Future<void> cancelDailyReminder() async {
    await init();
    try {
      await _plugin.cancel(id: dailyReminderId);
    } catch (_) {}
  }

  @override
  Future<void> replaceBillReminders(List<BillReminder> reminders) async {
    await init();
    try {
      final pending = await _plugin.pendingNotificationRequests();
      for (final p in pending) {
        if (p.id >= _billIdBase && p.id < _billIdBase + 1000) {
          await _plugin.cancel(id: p.id);
        }
      }
      final now = DateTime.now();
      for (final r in reminders) {
        if (!r.at.isAfter(now)) continue;
        await _plugin.zonedSchedule(
          id: _billIdBase + (r.id % 1000),
          title: r.title,
          body: r.body,
          scheduledDate: tz.TZDateTime.from(r.at, tz.local),
          notificationDetails: const NotificationDetails(
            android: _reminders,
            iOS: DarwinNotificationDetails(),
          ),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
      }
    } catch (e) {
      debugPrint('Could not schedule bill reminders: $e');
    }
  }

  @override
  Future<void> showNow({
    required int id,
    required String title,
    required String body,
    String? action,
  }) async {
    await init();
    try {
      await _plugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: const NotificationDetails(
          android: _alerts,
          iOS: DarwinNotificationDetails(),
        ),
        payload: action,
      );
    } catch (e) {
      debugPrint('Could not show a notification: $e');
    }
  }

  @override
  Stream<String> get taps => _taps.stream;

  @override
  Future<String?> launchAction() async {
    await init();
    try {
      final details = await _plugin.getNotificationAppLaunchDetails();
      if (details?.didNotificationLaunchApp ?? false) {
        return details!.notificationResponse?.payload;
      }
    } catch (_) {}
    return null;
  }
}

final appNotificationsProvider = Provider<AppNotifications>((ref) {
  return LocalNotifications();
});
