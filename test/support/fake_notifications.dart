import 'dart:async';

import 'package:flutter/material.dart' show TimeOfDay;
import 'package:accounts_note/core/services/notifications.dart';
import 'package:accounts_note/providers/app_lock_provider.dart';

/// Records what would be shown or scheduled. Shared by test/ and the Patrol
/// suite, where the real plugin would pop system UI.
class FakeNotifications implements AppNotifications {
  bool permission = true;
  TimeOfDay? dailyAt;
  List<BillReminder> bills = const [];
  final List<({int id, String title, String body, String? action})> shown = [];
  final _taps = StreamController<String>.broadcast();
  String? launchedWith;

  /// Simulates the user tapping a notification.
  void tap(String action) => _taps.add(action);

  @override
  Future<void> init() async {}

  @override
  Future<bool> requestPermission() async => permission;

  @override
  Future<void> scheduleDailyReminder(TimeOfDay at) async => dailyAt = at;

  @override
  Future<void> cancelDailyReminder() async => dailyAt = null;

  @override
  Future<void> replaceBillReminders(List<BillReminder> reminders) async =>
      bills = reminders;

  @override
  Future<void> showNow({
    required int id,
    required String title,
    required String body,
    String? action,
  }) async => shown.add((id: id, title: title, body: body, action: action));

  @override
  Stream<String> get taps => _taps.stream;

  @override
  Future<String?> launchAction() async => launchedWith;
}

/// Fingerprint unlock that answers as told, with no system prompt.
class FakeBiometrics implements BiometricUnlock {
  bool available = false;
  bool succeeds = true;
  int prompts = 0;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<bool> authenticate() async {
    prompts++;
    return available && succeeds;
  }
}
