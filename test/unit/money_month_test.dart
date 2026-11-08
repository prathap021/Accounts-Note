import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:accounts_note/core/utils/money_month.dart';
import 'package:accounts_note/providers/period_provider.dart';
import 'package:accounts_note/providers/settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('MoneyMonth', () {
    test('day 1 is the calendar month', () {
      final m = MoneyMonth.containing(DateTime(2026, 11, 7, 15));
      expect(m.start, DateTime(2026, 11, 1));
      expect(
        m.end,
        DateTime(2026, 12, 1).subtract(const Duration(milliseconds: 1)),
      );
      expect(m.label, 'November 2026');
      expect(m.key, '2026-11');
    });

    test('a pay day of the 25th runs from the 25th to the 24th', () {
      final before = MoneyMonth.containing(DateTime(2026, 11, 7), 25);
      expect(before.start, DateTime(2026, 10, 25));
      expect(before.end.day, 24);
      expect(before.end.month, 11);
      expect(before.label, '25 Oct – 24 Nov 2026');
      expect(before.key, '2026-10');

      final onPayDay = MoneyMonth.containing(DateTime(2026, 11, 25), 25);
      expect(onPayDay.start, DateTime(2026, 11, 25));
    });

    test('steps across year ends both ways', () {
      final jan = MoneyMonth.containing(DateTime(2027, 1, 10));
      expect(jan.previous().start, DateTime(2026, 12, 1));
      expect(jan.previous().next(), jan);
      final cycle = MoneyMonth.containing(DateTime(2026, 12, 30), 25);
      expect(cycle.label, '25 Dec 2026 – 24 Jan 2027');
      expect(cycle.next().start, DateTime(2027, 1, 25));
    });

    test('the start day is kept within 1–28, so February always works', () {
      expect(MoneyMonth.containing(DateTime(2026, 2, 27), 31).startDay, 28);
      final feb = MoneyMonth.containing(DateTime(2028, 2, 29), 28);
      expect(feb.start, DateTime(2028, 2, 28));
      expect(feb.contains(DateTime(2028, 3, 27, 23)), isTrue);
    });
  });

  group('the dashboard month', () {
    Future<ProviderContainer> container({int startDay = 1}) async {
      SharedPreferences.setMockInitialValues({'app_month_start_day': startDay});
      final prefs = await SharedPreferences.getInstance();
      final c = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('steps back, then forward, but never past this month', () async {
      final c = await container();
      final now = c.read(currentMoneyMonthProvider);
      final months = c.read(dashboardMonthOverrideProvider.notifier);

      months.next();
      expect(c.read(dashboardMonthProvider), now, reason: 'no future months');
      months.previous();
      months.previous();
      expect(c.read(dashboardMonthProvider), now.previous().previous());
      expect(c.read(isDashboardOnCurrentMonthProvider), isFalse);
      months.next();
      months.next();
      expect(c.read(isDashboardOnCurrentMonthProvider), isTrue);
    });

    test('follows the month start day setting', () async {
      final c = await container(startDay: 25);
      expect(c.read(currentMoneyMonthProvider).startDay, 25);
      await c.read(settingsProvider.notifier).setMonthStartDay(10);
      expect(c.read(currentMoneyMonthProvider).startDay, 10);
    });

    test('hiding amounts is remembered', () async {
      final c = await container();
      await c.read(settingsProvider.notifier).setHideBalance(true);
      expect(c.read(settingsProvider).hideBalance, isTrue);
    });
  });
}
