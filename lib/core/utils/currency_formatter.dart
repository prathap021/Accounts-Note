import 'package:intl/intl.dart';
import 'package:number_to_indian_words/number_to_indian_words.dart';

class CurrencyFormatter {
  /// Set [spacedSymbol] to separate the symbol from the digits ("₹ 1,605.00").
  /// Used where the amount is set large enough that a tight symbol crowds it,
  /// such as the dashboard balance.
  static String format(
    num amount, {
    String currencyCode = 'INR',
    bool spacedSymbol = false,
  }) {
    final symbol = symbolFor(currencyCode);
    final formatter = NumberFormat.currency(
      symbol: spacedSymbol && !symbol.endsWith(' ') ? '$symbol ' : symbol,
      decimalDigits: 2,
      locale: currencyCode == 'INR' ? 'en_IN' : 'en_US',
    );
    return formatter.format(amount);
  }

  /// Same as [format] but without the trailing decimals — used where space is
  /// tight (chart labels, compact stat rows).
  static String formatCompact(num amount, {String currencyCode = 'INR'}) {
    final formatter = NumberFormat.currency(
      symbol: symbolFor(currencyCode),
      decimalDigits: 0,
      locale: currencyCode == 'INR' ? 'en_IN' : 'en_US',
    );
    return formatter.format(amount);
  }

  /// Amount-in-words is Indian-numbering specific (lakh / crore), so it is
  /// only meaningful for INR.
  static bool supportsWords(String currencyCode) => currencyCode == 'INR';

  /// Amount in Indian words via [number_to_indian_words].
  /// Example: 125000 → "One Lakh Twenty Five Thousand rupees"
  static String inWords(num amount, {String currencyCode = 'INR'}) {
    final negative = amount < 0;
    final whole = amount.abs().round();

    if (whole == 0) {
      return currencyCode == 'INR' ? 'Zero rupees' : 'Zero';
    }

    final words = NumToWords.convertNumberToIndianWords(whole);
    final prefix = negative ? 'Minus ' : '';
    if (currencyCode == 'INR') {
      return '$prefix$words rupees';
    }
    return '$prefix$words';
  }

  static String symbolFor(String code) {
    switch (code) {
      case 'INR':
        return '₹';
      case 'USD':
        return '\$';
      case 'EUR':
        return '€';
      case 'GBP':
        return '£';
      default:
        return '$code ';
    }
  }
}
