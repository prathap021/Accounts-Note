import 'package:intl/intl.dart';
import 'package:number_to_indian_words/number_to_indian_words.dart';

class CurrencyFormatter {
  static String format(num amount, {String currencyCode = 'INR'}) {
    final symbol = _symbolFor(currencyCode);
    final formatter = NumberFormat.currency(
      symbol: symbol,
      decimalDigits: 2,
      locale: currencyCode == 'INR' ? 'en_IN' : 'en_US',
    );
    return formatter.format(amount);
  }

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

  static String _symbolFor(String code) {
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
