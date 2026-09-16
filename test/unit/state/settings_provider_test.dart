import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:income_expense_tracker/providers/settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Settings survive restarts, so both the in-memory state and what lands in
/// SharedPreferences are asserted.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<ProviderContainer> containerWith(
    Map<String, Object> initialValues,
  ) async {
    SharedPreferences.setMockInitialValues(initialValues);
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('defaults', () {
    test('a fresh install follows the system theme and uses INR', () async {
      final container = await containerWith({});
      final settings = container.read(settingsProvider);

      expect(settings.themeMode, ThemeMode.system);
      expect(settings.currency, 'INR');
      expect(settings.hasSeenOnboarding, isFalse);
    });
  });

  group('restoring', () {
    test('reads a previously saved theme', () async {
      final container = await containerWith({'app_theme_mode': 'dark'});
      expect(container.read(settingsProvider).themeMode, ThemeMode.dark);
    });

    test('reads a previously saved currency', () async {
      final container = await containerWith({'app_currency': 'USD'});
      expect(container.read(settingsProvider).currency, 'USD');
    });

    test('remembers that onboarding was completed', () async {
      final container =
          await containerWith({'app_has_seen_onboarding': true});
      expect(container.read(settingsProvider).hasSeenOnboarding, isTrue);
    });

    test('an unrecognised stored theme falls back to system', () async {
      final container = await containerWith({'app_theme_mode': 'rubbish'});
      expect(container.read(settingsProvider).themeMode, ThemeMode.system);
    });
  });

  group('updating', () {
    test('setThemeMode updates state and persists', () async {
      final container = await containerWith({});

      await container.read(settingsProvider.notifier).setThemeMode(
            ThemeMode.dark,
          );

      expect(container.read(settingsProvider).themeMode, ThemeMode.dark);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('app_theme_mode'), 'dark');
    });

    test('setCurrency updates state and persists', () async {
      final container = await containerWith({});

      await container.read(settingsProvider.notifier).setCurrency('EUR');

      expect(container.read(settingsProvider).currency, 'EUR');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('app_currency'), 'EUR');
    });

    test('setHasSeenOnboarding persists, so it is not shown twice', () async {
      final container = await containerWith({});

      await container
          .read(settingsProvider.notifier)
          .setHasSeenOnboarding(true);

      expect(container.read(settingsProvider).hasSeenOnboarding, isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('app_has_seen_onboarding'), isTrue);
    });

    test('changing one setting leaves the others alone', () async {
      final container = await containerWith({
        'app_currency': 'USD',
        'app_has_seen_onboarding': true,
      });

      await container
          .read(settingsProvider.notifier)
          .setThemeMode(ThemeMode.light);

      final settings = container.read(settingsProvider);
      expect(settings.themeMode, ThemeMode.light);
      expect(settings.currency, 'USD');
      expect(settings.hasSeenOnboarding, isTrue);
    });
  });
}
