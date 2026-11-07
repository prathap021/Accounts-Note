import 'dart:ui' show PlatformDispatcher;

/// A currency the app can keep accounts in.
class AppCurrency {
  final String code;
  final String name;

  /// As shown before amounts. Dollar currencies other than the US dollar
  /// carry a prefix ("CA$", "A$") so they cannot be mistaken for it.
  final String symbol;

  /// ISO 3166 country codes that use it, for picking a default from the
  /// device's region.
  final List<String> countries;

  const AppCurrency(this.code, this.name, this.symbol, this.countries);
}

/// Every local currency Google Play bills buyers in, with the countries it
/// bills in it, from Play's "Supported locations for distribution" table
/// (published 28 September 2026). Countries Play bills in US dollars (and
/// countries Play does not sell in) are not listed: they fall back to USD.
/// Update this when Play adds a buyer currency.
const kCurrencies = <AppCurrency>[
  AppCurrency('AED', 'UAE Dirham', 'AED ', ['AE']),
  AppCurrency('ARS', 'Argentine Peso', 'AR\$', ['AR']),
  AppCurrency('AUD', 'Australian Dollar', 'A\$', ['AU']),
  AppCurrency('AZN', 'Azerbaijani Manat', '₼', ['AZ']),
  AppCurrency('BDT', 'Bangladeshi Taka', '৳', ['BD']),
  AppCurrency('BOB', 'Bolivian Boliviano', 'Bs ', ['BO']),
  AppCurrency('BRL', 'Brazilian Real', 'R\$', ['BR']),
  AppCurrency('CAD', 'Canadian Dollar', 'CA\$', ['CA']),
  AppCurrency('CHF', 'Swiss Franc', 'CHF ', ['CH', 'LI']),
  AppCurrency('CLP', 'Chilean Peso', 'CL\$', ['CL']),
  AppCurrency('COP', 'Colombian Peso', 'CO\$', ['CO']),
  AppCurrency('CRC', 'Costa Rican Colón', '₡', ['CR']),
  AppCurrency('CZK', 'Czech Koruna', 'Kč ', ['CZ']),
  AppCurrency('DKK', 'Danish Krone', 'kr ', ['DK']),
  AppCurrency('DZD', 'Algerian Dinar', 'DZD ', ['DZ']),
  AppCurrency('EGP', 'Egyptian Pound', 'E£', ['EG']),
  AppCurrency('ETB', 'Ethiopian Birr', 'Br ', ['ET']),
  AppCurrency('EUR', 'Euro', '€', [
    'AT', 'BE', 'BF', 'BG', 'BJ', 'CY', 'DE', 'EE', 'ES', 'FI', 'FR', 'GA', //
    'GR', 'GW', 'HR', 'IE', 'IS', 'IT', 'LT', 'LU', 'LV', 'MC', 'ML', 'MT', //
    'NE', 'NL', 'PT', 'SI', 'SK', 'SM', 'TG', 'VA',
  ]),
  AppCurrency('GBP', 'British Pound', '£', ['GB', 'GI']),
  AppCurrency('GEL', 'Georgian Lari', '₾', ['GE']),
  AppCurrency('GHS', 'Ghanaian Cedi', 'GH₵', ['GH']),
  AppCurrency('HKD', 'Hong Kong Dollar', 'HK\$', ['HK']),
  AppCurrency('HUF', 'Hungarian Forint', 'Ft ', ['HU']),
  AppCurrency('IDR', 'Indonesian Rupiah', 'Rp ', ['ID']),
  AppCurrency('ILS', 'Israeli New Shekel', '₪', ['IL']),
  AppCurrency('INR', 'Indian Rupee', '₹', ['IN']),
  AppCurrency('IQD', 'Iraqi Dinar', 'IQD ', ['IQ']),
  AppCurrency('JOD', 'Jordanian Dinar', 'JOD ', ['JO']),
  AppCurrency('JPY', 'Japanese Yen', '¥', ['JP']),
  AppCurrency('KES', 'Kenyan Shilling', 'KSh ', ['KE']),
  AppCurrency('KRW', 'South Korean Won', '₩', ['KR']),
  AppCurrency('KZT', 'Kazakhstani Tenge', '₸', ['KZ']),
  AppCurrency('LKR', 'Sri Lankan Rupee', 'Rs ', ['LK']),
  AppCurrency('MAD', 'Moroccan Dirham', 'MAD ', ['MA']),
  AppCurrency('MMK', 'Myanmar Kyat', 'K ', ['MM']),
  AppCurrency('MNT', 'Mongolian Tögrög', '₮', ['MN']),
  AppCurrency('MOP', 'Macanese Pataca', 'MOP\$', ['MO']),
  AppCurrency('MXN', 'Mexican Peso', 'MX\$', ['MX']),
  AppCurrency('MYR', 'Malaysian Ringgit', 'RM ', ['MY']),
  AppCurrency('NGN', 'Nigerian Naira', '₦', ['NG']),
  AppCurrency('NOK', 'Norwegian Krone', 'kr ', ['NO']),
  AppCurrency('NZD', 'New Zealand Dollar', 'NZ\$', ['NZ']),
  AppCurrency('PEN', 'Peruvian Sol', 'S/ ', ['PE']),
  AppCurrency('PHP', 'Philippine Peso', '₱', ['PH']),
  AppCurrency('PKR', 'Pakistani Rupee', 'Rs ', ['PK']),
  AppCurrency('PLN', 'Polish Złoty', 'zł ', ['PL']),
  AppCurrency('PYG', 'Paraguayan Guaraní', '₲', ['PY']),
  AppCurrency('QAR', 'Qatari Riyal', 'QAR ', ['QA']),
  AppCurrency('RON', 'Romanian Leu', 'lei ', ['RO']),
  AppCurrency('RSD', 'Serbian Dinar', 'RSD ', ['RS']),
  AppCurrency('SAR', 'Saudi Riyal', 'SAR ', ['SA']),
  AppCurrency('SEK', 'Swedish Krona', 'kr ', ['SE']),
  AppCurrency('SGD', 'Singapore Dollar', 'S\$', ['SG']),
  AppCurrency('THB', 'Thai Baht', '฿', ['TH']),
  AppCurrency('TRY', 'Turkish Lira', '₺', ['TR']),
  AppCurrency('TWD', 'New Taiwan Dollar', 'NT\$', ['TW']),
  AppCurrency('TZS', 'Tanzanian Shilling', 'TSh ', ['TZ']),
  AppCurrency('UAH', 'Ukrainian Hryvnia', '₴', ['UA']),
  AppCurrency('USD', 'US Dollar', '\$', ['US']),
  AppCurrency('UZS', 'Uzbekistani Som', 'UZS ', ['UZ']),
  AppCurrency('VND', 'Vietnamese Dong', '₫', ['VN']),
  AppCurrency('XAF', 'Central African CFA Franc', 'FCFA ', ['CM']),
  AppCurrency('XOF', 'West African CFA Franc', 'CFA ', ['CI', 'SN']),
  AppCurrency('ZAR', 'South African Rand', 'R ', ['ZA']),
];

/// Shown first in the picker, after the user's own currency.
const kPopularCurrencyCodes = ['INR', 'USD', 'EUR', 'GBP'];

final Map<String, AppCurrency> _byCode = {
  for (final c in kCurrencies) c.code: c,
};

final Map<String, String> _byCountry = {
  for (final c in kCurrencies)
    for (final country in c.countries) country: c.code,
};

AppCurrency? currencyByCode(String code) => _byCode[code];

/// The currency used in [countryCode], or US dollars where Play does not sell
/// in a local currency.
String currencyForCountry(String? countryCode) =>
    _byCountry[countryCode?.toUpperCase()] ?? 'USD';

/// The device's region, e.g. "IN" for a phone set to English (India).
String? deviceCountryCode() {
  final locales = PlatformDispatcher.instance.locales;
  for (final l in locales) {
    final cc = l.countryCode;
    if (cc != null && cc.isNotEmpty) return cc.toUpperCase();
  }
  return null;
}
