import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/utils/money_month.dart';
import 'settings_provider.dart';

/// The budgeting month we are in now, honouring the month start day.
final currentMoneyMonthProvider = Provider<MoneyMonth>((ref) {
  final startDay = ref.watch(settingsProvider.select((s) => s.monthStartDay));
  return MoneyMonth.containing(DateTime.now(), startDay);
});

/// The month the dashboard shows, stepped with its ‹ › arrows. Null means
/// "the current one", so it moves on by itself when a new month starts.
class _DashboardMonthNotifier extends Notifier<MoneyMonth?> {
  @override
  MoneyMonth? build() {
    // A new start day re-cuts every month: go back to the current one.
    ref.watch(settingsProvider.select((s) => s.monthStartDay));
    return null;
  }

  MoneyMonth get _shown => state ?? ref.read(currentMoneyMonthProvider);

  void previous() => state = _shown.previous();

  /// Never past the current month: there is nothing to show yet.
  void next() {
    final current = ref.read(currentMoneyMonthProvider);
    final next = _shown.next();
    state = next.start.isAfter(current.start) || next == current ? null : next;
  }

  void showCurrent() => state = null;
}

final dashboardMonthOverrideProvider =
    NotifierProvider<_DashboardMonthNotifier, MoneyMonth?>(
      _DashboardMonthNotifier.new,
    );

final dashboardMonthProvider = Provider<MoneyMonth>((ref) {
  return ref.watch(dashboardMonthOverrideProvider) ??
      ref.watch(currentMoneyMonthProvider);
});

final isDashboardOnCurrentMonthProvider = Provider<bool>((ref) {
  return ref.watch(dashboardMonthOverrideProvider) == null;
});
