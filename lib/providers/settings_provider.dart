import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('Initialize this in main.dart');
});

class AppSettings {
  final ThemeMode themeMode;
  final String currency;
  final bool hasSeenOnboarding;

  const AppSettings({
    required this.themeMode,
    required this.currency,
    required this.hasSeenOnboarding,
  });

  AppSettings copyWith({
    ThemeMode? themeMode,
    String? currency,
    bool? hasSeenOnboarding,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      currency: currency ?? this.currency,
      hasSeenOnboarding: hasSeenOnboarding ?? this.hasSeenOnboarding,
    );
  }
}

class SettingsNotifier extends Notifier<AppSettings> {
  static const _themeKey = 'app_theme_mode';
  static const _currencyKey = 'app_currency';
  static const _onboardingKey = 'app_has_seen_onboarding';

  @override
  AppSettings build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    final themeStr = prefs.getString(_themeKey) ?? 'system';
    final currency = prefs.getString(_currencyKey) ?? 'INR';
    final hasSeenOnboarding = prefs.getBool(_onboardingKey) ?? false;

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

  Future<void> setHasSeenOnboarding(bool value) async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setBool(_onboardingKey, value);
    state = state.copyWith(hasSeenOnboarding: value);
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(
  SettingsNotifier.new,
);
