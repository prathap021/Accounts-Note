import 'dart:convert';

import 'package:excel/excel.dart';
import 'package:flutter/material.dart' show DateTimeRange;
import 'package:flutter_test/flutter_test.dart';
import 'package:income_expense_tracker/core/constants/app_constants.dart';
import 'package:income_expense_tracker/features/reports/report_export.dart';

import '../support/fixtures.dart';

/// Whole amounts read back as integers, fractional ones as doubles; both are
/// numbers in the sheet, which is what matters.
num number(CellValue? v) => switch (v) {
  IntCellValue(:final value) => value,
  DoubleCellValue(:final value) => value,
  _ => throw TestFailure('not a number: $v'),
};

void main() {
  final march = DateTimeRange(
    start: DateTime(2025, 3, 1),
    end: DateTime(2025, 3, 31, 23, 59, 59, 999),
  );

  ReportData report() => ReportData(
    range: march,
    periodLabel: '1 Mar 2025 – 31 Mar 2025',
    currency: 'INR',
    transactions: [
      txFixture(
        id: 'pay',
        type: TransactionType.income,
        amount: 5000,
        categoryName: 'Salary',
        note: null,
        date: DateTime(2025, 3, 10, 9),
      ),
      txFixture(
        id: 'late',
        amount: 750,
        note: 'Dinner ₹ घर',
        date: DateTime(2025, 3, 31, 21, 45),
      ),
      txFixture(id: 'april', amount: 999, date: DateTime(2025, 4, 1)),
      txFixture(id: 'feb', amount: 111, date: DateTime(2025, 2, 28, 23)),
    ],
  );

  test('a report holds only the period, oldest first, with its totals', () {
    final r = report();
    expect(r.transactions.map((t) => t.id), ['pay', 'late']);
    expect(r.income, 5000);
    expect(r.expense, 750);
    expect(r.net, 4250);
    expect(
      r.fileName(ReportFormat.pdf),
      'accounts_note_report_2025-03-01_2025-03-31.pdf',
    );
    expect(r.fileName(ReportFormat.excel), endsWith('.xlsx'));
  });

  test('CSV has a header and one row per entry', () {
    final lines = const LineSplitter().convert(
      utf8.decode(ReportExporter.buildCsv(report())),
    );
    expect(lines.first, startsWith('Date,Type,Category,Amount'));
    expect(lines, hasLength(3));
    expect(lines[1], contains('Income'));
    expect(lines[1], contains('5000'));
  });

  test('Excel has a summary sheet and a transactions sheet', () {
    final book = Excel.decodeBytes(ReportExporter.buildExcel(report()));
    expect(book.tables.keys, containsAll(['Summary', 'Transactions']));
    expect(book.tables.keys, isNot(contains('Sheet1')));

    final summary = book.tables['Summary']!.rows;
    String label(int r) => summary[r][0]!.value.toString();
    num amount(int r) => number(summary[r][1]!.value);
    expect(label(3), 'Income');
    expect(amount(3), 5000);
    expect(label(4), 'Expenses');
    expect(amount(4), 750);
    expect(label(5), 'Net');
    expect(amount(5), 4250);

    final rows = book.tables['Transactions']!.rows;
    expect(rows, hasLength(3), reason: 'header and two entries');
    expect(rows[1][2]!.value.toString(), 'Salary');
    expect(
      number(rows[2][3]!.value),
      750,
      reason: 'amounts stay numbers',
    );
  });

  test('PDF is a real PDF document', () async {
    final bytes = await ReportExporter.buildPdf(report());
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    expect(bytes.length, greaterThan(1000));
  });

  test('an empty period still makes a PDF', () async {
    final empty = ReportData(
      range: march,
      periodLabel: 'March',
      currency: 'INR',
      transactions: const [],
    );
    expect(empty.isEmpty, isTrue);
    final bytes = await ReportExporter.buildPdf(empty);
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });

  test('text the PDF fonts cannot draw is replaced, not dropped', () {
    expect(ReportExporter.pdfSafe('Dinner ₹ घर – café'), 'Dinner ? ?? – café');
  });
}
