import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants/currencies.dart';

/// The phone's region ("IN", "US"…), for country-based defaults.
final deviceCountryProvider = Provider<String?>((ref) => deviceCountryCode());

final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('Initialize this in main.dart');
});

class AppSettings {
  final ThemeMode themeMode;
  final String currency;
  final bool hasSeenOnboarding;

  /// The day budgeting months start on (1–28), e.g. 25 for a salary paid on
  /// the 25th. 1 is the calendar month.
  final int monthStartDay;

  /// Masks the balance and totals on the dashboard, for using the app in
  /// public.
  final bool hideBalance;

  const AppSettings({
    required this.themeMode,
    required this.currency,
    required this.hasSeenOnboarding,
    this.monthStartDay = 1,
    this.hideBalance = false,
  });

  AppSettings copyWith({
    ThemeMode? themeMode,
    String? currency,
    bool? hasSeenOnboarding,
    int? monthStartDay,
    bool? hideBalance,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      currency: currency ?? this.currency,
      hasSeenOnboarding: hasSeenOnboarding ?? this.hasSeenOnboarding,
      monthStartDay: monthStartDay ?? this.monthStartDay,
      hideBalance: hideBalance ?? this.hideBalance,
    );
  }
}

class SettingsNotifier extends Notifier<AppSettings> {
  static const _themeKey = 'app_theme_mode';
  static const _currencyKey = 'app_currency';
  static const _onboardingKey = 'app_has_seen_onboarding';
  static const _monthStartKey = 'app_month_start_day';
  static const _hideBalanceKey = 'app_hide_balance';

  @override
  AppSettings build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    final themeStr = prefs.getString(_themeKey) ?? 'system';
    final hasSeenOnboarding = prefs.getBool(_onboardingKey) ?? false;
    // A new install starts in the money of the phone's country. Anyone who
    // already used the app keeps what they had (INR was the only default),
    // so their amounts never change symbol under them.
    final currency = prefs.getString(_currencyKey) ??
        (hasSeenOnboarding
            ? 'INR'
            : currencyForCountry(ref.watch(deviceCountryProvider)));

    ThemeMode mode;
    switch (themeStr) {
      case 'light':
        mode = ThemeMode.light;
        break;
      case 'dark':
        mode = ThemeMode.dark;
        break;
      default:
        mode = ThemeMode.system;
    }

    return AppSettings(
      themeMode: mode,
      currency: currency,
      hasSeenOnboarding: hasSeenOnboarding,
      monthStartDay: prefs.getInt(_monthStartKey) ?? 1,
      hideBalance: prefs.getBool(_hideBalanceKey) ?? false,
    );
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setString(_themeKey, mode.name);
    state = state.copyWith(themeMode: mode);
  }

  Future<void> setCurrency(String currency) async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setString(_currencyKey, currency);
    state = state.copyWith(currency: currency);
  }

  Future<void> setMonthStartDay(int day) async {
    final d = day < 1 ? 1 : (day > 28 ? 28 : day);
    await ref.read(sharedPreferencesProvider).setInt(_monthStartKey, d);
    state = state.copyWith(monthStartDay: d);
  }

  Future<void> setHideBalance(bool hide) async {
    await ref.read(sharedPreferencesProvider).setBool(_hideBalanceKey, hide);
    state = state.copyWith(hideBalance: hide);
  }

  Future<void> setHasSeenOnboarding(bool value) async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setBool(_onboardingKey, value);
    // Pin the country default now, so it does not move if the phone's
    // region changes later.
    if (value && prefs.getString(_currencyKey) == null) {
      await prefs.setString(_currencyKey, state.currency);
    }
    state = state.copyWith(hasSeenOnboarding: value);
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(
  SettingsNotifier.new,
);
