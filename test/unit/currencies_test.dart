import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:income_expense_tracker/core/constants/currencies.dart';
import 'package:income_expense_tracker/core/utils/currency_formatter.dart';
import 'package:income_expense_tracker/models/subscription_plan.dart';
import 'package:income_expense_tracker/providers/settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('currency list', () {
    test('every Play currency is listed once, with a symbol', () {
      final codes = kCurrencies.map((c) => c.code).toList();
      expect(codes.toSet(), hasLength(codes.length));
      expect(codes, containsAll(['INR', 'USD', 'EUR', 'GBP', 'JPY', 'BRL']));
      expect(kCurrencies.length, greaterThan(50));
      for (final c in kCurrencies) {
        expect(c.symbol.trim(), isNotEmpty, reason: c.code);
        expect(
          () => CurrencyFormatter.format(1234.5, currencyCode: c.code),
          returnsNormally,
          reason: c.code,
        );
      }
    });

    test("a country maps to its own currency, else US dollars", () {
      expect(currencyForCountry('IN'), 'INR');
      expect(currencyForCountry('us'), 'USD');
      expect(currencyForCountry('DE'), 'EUR');
      expect(currencyForCountry('BG'), 'EUR', reason: 'euro since 2026');
      expect(currencyForCountry('GB'), 'GBP');
      expect(currencyForCountry('JP'), 'JPY');
      expect(currencyForCountry('FJ'), 'USD', reason: 'Play bills in USD');
      expect(currencyForCountry(null), 'USD');
    });

    test("follows Play's own billing currency per country", () {
      expect(currencyForCountry('BJ'), 'EUR', reason: 'Benin is billed in EUR');
      expect(currencyForCountry('IS'), 'EUR');
      expect(currencyForCountry('GI'), 'GBP');
      expect(currencyForCountry('CM'), 'XAF');
      expect(currencyForCountry('CI'), 'XOF');
      expect(currencyForCountry('UZ'), 'UZS');
      expect(currencyForCountry('MO'), 'MOP');
      expect(currencyForCountry('KW'), 'USD', reason: 'billed in USD');
      expect(currencyForCountry('RU'), 'USD', reason: 'no Play purchases');
    });
  });

  group('default currency', () {
    Future<(ProviderContainer, SharedPreferences)> settings({
      required String? country,
      Map<String, Object> saved = const {},
    }) async {
      SharedPreferences.setMockInitialValues(saved);
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          deviceCountryProvider.overrideWithValue(country),
        ],
      );
      addTearDown(container.dispose);
      return (container, prefs);
    }

    test("a new install starts in the phone's country currency", () async {
      final (india, _) = await settings(country: 'IN');
      expect(india.read(settingsProvider).currency, 'INR');
      final (germany, _) = await settings(country: 'DE');
      expect(germany.read(settingsProvider).currency, 'EUR');
      final (usa, _) = await settings(country: 'US');
      expect(usa.read(settingsProvider).currency, 'USD');
    });

    test('an existing user keeps INR, whatever the phone says', () async {
      final (c, _) = await settings(
        country: 'US',
        saved: {'app_has_seen_onboarding': true},
      );
      expect(c.read(settingsProvider).currency, 'INR');
    });

    test('a chosen currency always wins', () async {
      final (c, _) = await settings(
        country: 'IN',
        saved: {'app_currency': 'GBP'},
      );
      expect(c.read(settingsProvider).currency, 'GBP');
    });

    test('finishing onboarding pins the country default', () async {
      final (c, prefs) = await settings(country: 'DE');
      await c.read(settingsProvider.notifier).setHasSeenOnboarding(true);
      expect(prefs.getString('app_currency'), 'EUR');
    });
  });

  test('plan list prices: rupees for INR, dollars for everything else', () {
    expect(SubscriptionPlan.basic.listPrice('INR'), '₹99');
    expect(SubscriptionPlan.standard.listPrice('INR'), '₹199');
    expect(SubscriptionPlan.premium.listPrice('INR'), '₹299');
    expect(SubscriptionPlan.basic.listPrice('USD'), '\$1');
    expect(SubscriptionPlan.standard.listPrice('EUR'), '\$2');
    expect(SubscriptionPlan.premium.listPrice('JPY'), '\$3');
  });
}
