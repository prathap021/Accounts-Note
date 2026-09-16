import 'package:flutter_test/flutter_test.dart';
import 'package:income_expense_tracker/core/utils/currency_formatter.dart';

/// Money formatting is shown on nearly every screen, so a regression here is
/// both highly visible and easy to introduce.
void main() {
  group('symbolFor', () {
    test('maps the supported currencies', () {
      expect(CurrencyFormatter.symbolFor('INR'), '₹');
      expect(CurrencyFormatter.symbolFor('USD'), '\$');
      expect(CurrencyFormatter.symbolFor('EUR'), '€');
      expect(CurrencyFormatter.symbolFor('GBP'), '£');
    });

    test('falls back to the code itself for anything unknown', () {
      expect(CurrencyFormatter.symbolFor('JPY'), 'JPY ');
    });
  });

  group('format', () {
    test('uses Indian digit grouping for INR', () {
      expect(CurrencyFormatter.format(120000, currencyCode: 'INR'),
          '₹1,20,000.00');
    });

    test('uses western grouping for USD', () {
      expect(CurrencyFormatter.format(120000, currencyCode: 'USD'),
          '\$120,000.00');
    });

    test('always shows two decimals', () {
      expect(CurrencyFormatter.format(5), '₹5.00');
      expect(CurrencyFormatter.format(5.5), '₹5.50');
    });

    test('keeps the sign on negative amounts', () {
      expect(CurrencyFormatter.format(-250).startsWith('-'), isTrue);
    });

    test('defaults to INR when no code is given', () {
      expect(CurrencyFormatter.format(10), CurrencyFormatter.format(10,
          currencyCode: 'INR'));
    });
  });

  group('spacedSymbol', () {
    test('separates the symbol from the digits when asked', () {
      expect(
        CurrencyFormatter.format(1605, currencyCode: 'INR', spacedSymbol: true),
        '₹ 1,605.00',
      );
    });

    test('is off by default, so compact rows stay tight', () {
      expect(CurrencyFormatter.format(1605), '₹1,605.00');
    });

    test('does not double the gap for symbols that already end in a space', () {
      final spaced =
          CurrencyFormatter.format(10, currencyCode: 'JPY', spacedSymbol: true);
      expect(spaced.contains('  '), isFalse);
    });
  });

  group('formatCompact', () {
    test('drops the decimals', () {
      expect(CurrencyFormatter.formatCompact(3395), '₹3,395');
    });

    test('rounds rather than truncating', () {
      expect(CurrencyFormatter.formatCompact(3395.6), '₹3,396');
    });
  });

  group('words', () {
    test('are only offered for INR', () {
      expect(CurrencyFormatter.supportsWords('INR'), isTrue);
      expect(CurrencyFormatter.supportsWords('USD'), isFalse);
    });

    test('render Indian units', () {
      expect(CurrencyFormatter.inWords(120000), contains('Lakh'));
      expect(CurrencyFormatter.inWords(1605), contains('Thousand'));
    });

    test('handle zero and negatives', () {
      expect(CurrencyFormatter.inWords(0), 'Zero rupees');
      expect(CurrencyFormatter.inWords(-500), startsWith('Minus'));
    });
  });
}
