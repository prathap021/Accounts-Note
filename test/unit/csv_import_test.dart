import 'package:flutter_test/flutter_test.dart';
import 'package:accounts_note/core/constants/app_constants.dart';
import 'package:accounts_note/data/repositories/csv_import_repository.dart';

void main() {
  group('reading CSV files', () {
    test("this app's own report export reads back", () {
      final p = CsvImportParser.parse(
        'Date,Type,Category,Amount,Payment method,Credit card,Note\r\n'
        '2026-10-01 09:30,Income,Salary,52000.0,Bank Transfer,,October pay\r\n'
        '2026-10-02 13:05,Expense,Food,450.5,UPI,,"Lunch, team"\r\n',
      );
      expect(p.entries, hasLength(2));
      expect(p.income, 1);
      final lunch = p.entries[1];
      expect(lunch.type, TransactionType.expense);
      expect(lunch.amount, 450.5);
      expect(lunch.category, 'Food');
      expect(lunch.note, 'Lunch, team');
      expect(lunch.paymentMethod, 'UPI');
      expect(lunch.date, DateTime(2026, 10, 2, 13, 5));
    });

    test('a bank statement with title lines and Debit/Credit columns', () {
      final p = CsvImportParser.parse(
        'HDFC Bank statement\n'
        'Account: XXXX1234\n'
        '\n'
        'Date,Narration,Withdrawal Amt.,Deposit Amt.,Closing Balance\n'
        '03/10/26,UPI-SWIGGY,"1,250.00",,48750.00\n'
        '05/10/26,NEFT SALARY,,"52,000.00",100750.00\n'
        'Total,,1250,52000,\n',
      );
      expect(p.entries, hasLength(2));
      expect(p.skipped, 1, reason: 'the Total line has no date');
      expect(p.entries[0].type, TransactionType.expense);
      expect(p.entries[0].amount, 1250);
      expect(p.entries[0].date, DateTime(2026, 10, 3), reason: 'day first');
      expect(p.entries[0].note, 'UPI-SWIGGY');
      expect(p.entries[0].category, 'Other');
      expect(p.entries[1].type, TransactionType.income);
      expect(p.entries[1].amount, 52000);
    });

    test('a signed Amount column: minus is spending, plus is income', () {
      final p = CsvImportParser.parse(
        'date,amount,description,category\n'
        '2026-10-01,-300,Groceries,Food\n'
        '2026-10-02,1200,Refund,Gift\n',
      );
      expect(p.entries.map((e) => e.type), [
        TransactionType.expense,
        TransactionType.income,
      ]);
    });

    test('unsigned amounts with no type are all spending', () {
      final p = CsvImportParser.parse(
        'Date,Amount,Note\n12 Oct 2026,₹99,Tea\n13-Oct-2026,45.00,Bus\n',
      );
      expect(p.entries.every((e) => e.type == TransactionType.expense), isTrue);
      expect(p.entries.map((e) => e.amount), [99, 45]);
      expect(p.first, DateTime(2026, 10, 12));
      expect(p.last, DateTime(2026, 10, 13));
    });

    test('amounts in the usual written forms', () {
      expect(CsvImportParser.parseAmount('₹1,200.50'), 1200.5);
      expect(CsvImportParser.parseAmount('(45)'), -45);
      expect(CsvImportParser.parseAmount('-45'), -45);
      expect(CsvImportParser.parseAmount('450.00 Dr'), -450);
      expect(CsvImportParser.parseAmount(''), isNull);
      expect(CsvImportParser.parseDate('03-10-26'), DateTime(2026, 10, 3));
      expect(CsvImportParser.parseDate('2026/10/03'), DateTime(2026, 10, 3));
      expect(CsvImportParser.parseDate('tomorrow'), isNull);
    });

    test('a file without a date or amount column is refused with a reason', () {
      expect(
        () => CsvImportParser.parse('Name,Total\nTea,10\n'),
        throwsA(
          isA<CsvFormatException>().having(
            (e) => e.message,
            'message',
            contains('No Date column'),
          ),
        ),
      );
      expect(
        () => CsvImportParser.parse('Date,Note\n2026-10-01,Tea\n'),
        throwsA(isA<CsvFormatException>()),
      );
      expect(
        () => CsvImportParser.parse(''),
        throwsA(isA<CsvFormatException>()),
      );
    });

    test('Cr/Dr markers set the type', () {
      final p = CsvImportParser.parse(
        'Txn Date,Dr/Cr,Amount\n2026-10-01,CR,500\n2026-10-02,DR,80\n',
      );
      expect(p.entries.map((e) => e.type), [
        TransactionType.income,
        TransactionType.expense,
      ]);
    });
  });
}
