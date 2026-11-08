import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:accounts_note/core/services/country_locator.dart';
import 'package:accounts_note/features/onboarding/currency_setup_dialog.dart';
import 'package:accounts_note/providers/settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeLocator implements CountryLocator {
  _FakeLocator(this.country);
  final String? country;
  int calls = 0;

  @override
  Future<String?> countryFromLocation() async {
    calls++;
    return country;
  }
}

/// First run: the currency from the phone's location, or its region.
void main() {
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  Future<_FakeLocator> pump(
    WidgetTester tester, {
    required String? located,
    String region = 'US',
  }) async {
    final locator = _FakeLocator(located);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          deviceCountryProvider.overrideWithValue(region),
          countryLocatorProvider.overrideWithValue(locator),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => TextButton(
                onPressed: () => chooseStartingCurrency(context, ref),
                child: const Text('start'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('start'));
    await tester.pumpAndSettle();
    return locator;
  }

  testWidgets("explains the use of location and offers the region's currency", (
    tester,
  ) async {
    await pump(tester, located: 'IN');
    expect(find.text('Set your currency'), findsOneWidget);
    expect(find.textContaining("isn't saved or sent anywhere"), findsOneWidget);
    expect(find.textContaining('US Dollar (\$)'), findsOneWidget);
  });

  testWidgets('the location decides the currency', (tester) async {
    final locator = await pump(tester, located: 'IN', region: 'US');
    await tester.tap(find.text('Use my location'));
    await tester.pumpAndSettle();

    expect(locator.calls, 1);
    expect(prefs.getString('app_currency'), 'INR');
    expect(
      find.textContaining('Currency set to Indian Rupee (₹)'),
      findsOneWidget,
    );
  });

  testWidgets('a country Play bills in CFA francs gets them', (tester) async {
    await pump(tester, located: 'SN', region: 'US');
    await tester.tap(find.text('Use my location'));
    await tester.pumpAndSettle();
    expect(
      prefs.getString('app_currency'),
      'XOF',
      reason: 'Senegal is billed in West African CFA francs',
    );
  });

  testWidgets('without a location, the region currency stays', (tester) async {
    await pump(tester, located: null, region: 'DE');
    await tester.tap(find.text('Use my location'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining("Couldn't find your location. Keeping Euro"),
      findsOneWidget,
    );
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Set your currency'), findsNothing);
    expect(
      prefs.getString('app_currency'),
      isNull,
      reason: 'the region default is pinned when onboarding finishes',
    );
  });

  testWidgets('"Not now" never asks for location', (tester) async {
    final locator = await pump(tester, located: 'IN');
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(locator.calls, 0);
    expect(prefs.getString('app_currency'), isNull);
  });
}
