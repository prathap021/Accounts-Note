import 'package:flutter_test/flutter_test.dart';
import 'package:accounts_note/core/constants/app_constants.dart';
import 'package:accounts_note/models/transaction_totals.dart';
import 'package:accounts_note/providers/credit_card_provider.dart';

import '../support/fixtures.dart';

/// The two sums the credit card feature shows: the total for whatever
/// Activity is filtered to, and each card's spend this month.
void main() {
  final hdfc = creditCardFixture();
  final sbi = creditCardFixture(id: 'card-sbi', name: 'SBI', last4: '9876');

  group('TransactionTotals', () {
    test('keeps money in and money out apart, and counts entries', () {
      final totals = TransactionTotals.of([
        txFixture(id: 'a', amount: 1200),
        txFixture(id: 'b', amount: 300),
        txFixture(id: 'c', type: TransactionType.income, amount: 200),
      ]);

      expect(totals.expense, 1500);
      expect(totals.income, 200);
      expect(totals.net, -1300);
      expect(totals.count, 3);
    });

    test('nothing matched is an empty total, not an error', () {
      final totals = TransactionTotals.of(const []);

      expect(totals.isEmpty, isTrue);
      expect(totals.net, 0);
    });
  });

  group('creditCardSpendFor', () {
    test('adds up each card separately', () {
      final spend = creditCardSpendFor([
        cardTxFixture(hdfc, id: 'h1', amount: 1200),
        cardTxFixture(hdfc, id: 'h2', amount: 800),
        cardTxFixture(sbi, id: 's1', amount: 300),
      ], now: fixedNow);

      expect(spend, {'card-hdfc': 2000, 'card-sbi': 300});
    });

    test('a refund to the card is not spending', () {
      final spend = creditCardSpendFor([
        cardTxFixture(hdfc, id: 'h1', amount: 1200),
        cardTxFixture(hdfc,
            id: 'refund', type: TransactionType.income, amount: 200),
      ], now: fixedNow);

      expect(spend['card-hdfc'], 1200);
    });

    test('ignores anything not paid by card', () {
      final spend = creditCardSpendFor([txFixture(amount: 500)], now: fixedNow);

      expect(spend, isEmpty);
    });

    test('counts this month only, both ends included', () {
      final spend = creditCardSpendFor([
        cardTxFixture(hdfc, id: 'first', amount: 1, date: DateTime(2026, 9, 1)),
        cardTxFixture(hdfc,
            id: 'last', amount: 10, date: DateTime(2026, 9, 30, 23, 59)),
        cardTxFixture(hdfc,
            id: 'before', amount: 100, date: DateTime(2026, 8, 31, 23, 59)),
        cardTxFixture(hdfc, id: 'after', amount: 1000, date: DateTime(2026, 10, 1)),
      ], now: fixedNow);

      expect(spend['card-hdfc'], 11);
    });
  });

  group('monthRangeFor', () {
    test('December runs to the 31st, not into January', () {
      final range = monthRangeFor(DateTime(2026, 12, 10));

      expect(range.start, DateTime(2026, 12, 1));
      expect(range.end, DateTime(2026, 12, 31, 23, 59, 59, 999));
    });

    test('a leap-year February ends on the 29th', () {
      expect(monthRangeFor(DateTime(2028, 2, 3)).end.day, 29);
    });
  });
}
