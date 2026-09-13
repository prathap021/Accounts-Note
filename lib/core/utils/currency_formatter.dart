import 'package:intl/intl.dart';

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
