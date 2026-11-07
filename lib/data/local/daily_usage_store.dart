import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/app_constants.dart';
import '../../models/daily_usage.dart';

/// Entries this device has added that the server has not counted yet.
///
/// The server's per-day counter only moves when an entry is uploaded, so on
/// its own it would let someone offline add without limit. This keeps the
/// gap: +1 when an entry is created here, -1 when its upload (and the
/// counter bump that goes with it) succeeds. What the user has used today is
/// the server's count plus this.
///
/// An entry deleted before it was uploaded is never subtracted. Deleting does
/// not hand an entry back, online or off, so the two paths agree.
class DailyUsageStore {
  DailyUsageStore(this._prefs);

  final SharedPreferences _prefs;

  final _changes = StreamController<void>.broadcast();

  /// Fires after every change, so what-is-left-today can be recomputed.
  Stream<void> get changes => _changes.stream;

  static const _prefix = 'daily_usage_unsynced';

  /// Days kept besides today. Older entries can no longer be uploaded (the
  /// rules accept entries up to three days late), so their counts are noise.
  static const _keepDays = 4;

  String _key(String uid, String day) => '$_prefix.$uid.$day';

  DailyUsage unsynced(String uid, String day) {
    final raw = _prefs.getString(_key(uid, day));
    if (raw == null) return DailyUsage(day: day);
    try {
      return DailyUsage.fromMap(day, jsonDecode(raw) as Map<String, dynamic>);
    } on FormatException {
      return DailyUsage(day: day);
    }
  }

  Future<void> recordCreated(String uid, String day, TransactionType type) =>
      _adjust(uid, day, type, 1);

  Future<void> recordUploaded(String uid, String day, TransactionType type) =>
      _adjust(uid, day, type, -1);

  Future<void> _adjust(
    String uid,
    String day,
    TransactionType type,
    int delta,
  ) async {
    final current = unsynced(uid, day);
    int next(int value) => (value + delta).clamp(0, 1 << 30);
    final updated = DailyUsage(
      day: day,
      income: type == TransactionType.income
          ? next(current.income)
          : current.income,
      expense: type == TransactionType.expense
          ? next(current.expense)
          : current.expense,
    );
    final key = _key(uid, day);
    if (updated.income == 0 && updated.expense == 0) {
      await _prefs.remove(key);
    } else {
      await _prefs.setString(
        key,
        jsonEncode({'income': updated.income, 'expense': updated.expense}),
      );
    }
    await _prune(uid);
    if (!_changes.isClosed) _changes.add(null);
  }

  Future<void> _prune(String uid) async {
    final oldest = todayKey(
      DateTime.now().subtract(const Duration(days: _keepDays)),
    );
    final userPrefix = '$_prefix.$uid.';
    for (final key in _prefs.getKeys().toList()) {
      if (!key.startsWith(userPrefix)) continue;
      // yyyy-MM-dd sorts the same as the dates it names.
      if (key.substring(userPrefix.length).compareTo(oldest) < 0) {
        await _prefs.remove(key);
      }
    }
  }

  /// Forgets everything for [uid] — on sign-out, with the rest of the device
  /// copy.
  Future<void> clear(String uid) async {
    final userPrefix = '$_prefix.$uid.';
    for (final key in _prefs.getKeys().toList()) {
      if (key.startsWith(userPrefix)) await _prefs.remove(key);
    }
    if (!_changes.isClosed) _changes.add(null);
  }

  Future<void> dispose() => _changes.close();
}
