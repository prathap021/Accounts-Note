import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:excel/excel.dart';
import 'package:flutter/material.dart' show DateTimeRange;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../../core/constants/app_constants.dart';
import '../../models/transaction_model.dart';

/// The file types a report can be exported as.
enum ReportFormat {
  pdf('PDF document', 'pdf', 'application/pdf'),
  excel(
    'Excel spreadsheet',
    'xlsx',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  ),
  csv('CSV file', 'csv', 'text/csv');

  const ReportFormat(this.label, this.extension, this.mimeType);

  final String label;
  final String extension;
  final String mimeType;
}

/// Everything a report file shows: the period, its totals and its entries.
class ReportData {
  ReportData({
    required this.range,
    required this.periodLabel,
    required this.currency,
    required Iterable<TransactionModel> transactions,
  }) : transactions =
           transactions
               .where(
                 (t) =>
                     !t.date.isBefore(range.start) &&
                     !t.date.isAfter(range.end),
               )
               .toList()
             ..sort((a, b) => a.date.compareTo(b.date));

  final DateTimeRange range;

  /// As shown on screen, e.g. "1 Mar 2025 – 31 Mar 2025".
  final String periodLabel;
  final String currency;

  /// The entries dated inside [range], oldest first.
  final List<TransactionModel> transactions;

  double _sum(TransactionType type) => transactions
      .where((t) => t.type == type)
      .fold(0, (sum, t) => sum + t.amount);

  double get income => _sum(TransactionType.income);
  double get expense => _sum(TransactionType.expense);
  double get net => income - expense;

  bool get isEmpty => transactions.isEmpty;

  /// e.g. `accounts_note_report_2025-03-01_2025-03-31.pdf`.
  String fileName(ReportFormat format) {
    final d = DateFormat('yyyy-MM-dd');
    return 'accounts_note_report_${d.format(range.start)}_'
        '${d.format(range.end)}.${format.extension}';
  }
}

/// Builds report files. Pure apart from [share], so each format can be tested
/// on its bytes.
class ReportExporter {
  static const _headers = [
    'Date',
    'Type',
    'Category',
    'Amount',
    'Payment method',
    'Credit card',
    'Note',
  ];

  static final _dateTime = DateFormat('yyyy-MM-dd HH:mm');

  static String _type(TransactionModel t) =>
      t.type == TransactionType.income ? 'Income' : 'Expense';

  static Future<Uint8List> build(ReportData data, ReportFormat format) async =>
      switch (format) {
        ReportFormat.pdf => await buildPdf(data),
        ReportFormat.excel => buildExcel(data),
        ReportFormat.csv => buildCsv(data),
      };

  static Uint8List buildCsv(ReportData data) {
    final rows = <List<dynamic>>[
      _headers,
      for (final t in data.transactions)
        [
          _dateTime.format(t.date),
          _type(t),
          t.categoryName,
          t.amount,
          t.paymentMethod ?? '',
          t.creditCardName ?? '',
          t.note ?? '',
        ],
    ];
    return Uint8List.fromList(utf8.encode(Csv().encode(rows)));
  }

  /// Two sheets: a summary of the period, and every entry in it. Amounts are
  /// numbers, so the spreadsheet can total and chart them.
  static Uint8List buildExcel(ReportData data) {
    final excel = Excel.createExcel();
    final defaultSheet = excel.getDefaultSheet();

    final summary = excel['Summary'];
    final bold = CellStyle(bold: true);
    void row(Sheet sheet, List<CellValue> cells, {bool header = false}) {
      sheet.appendRow(cells);
      if (!header) return;
      final r = sheet.maxRows - 1;
      for (var c = 0; c < cells.length; c++) {
        sheet
                .cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r))
                .cellStyle =
            bold;
      }
    }

    row(summary, [TextCellValue('Accounts Note report')], header: true);
    row(summary, [TextCellValue('Period'), TextCellValue(data.periodLabel)]);
    row(summary, [TextCellValue('Currency'), TextCellValue(data.currency)]);
    row(summary, [TextCellValue('Income'), DoubleCellValue(data.income)]);
    row(summary, [TextCellValue('Expenses'), DoubleCellValue(data.expense)]);
    row(summary, [TextCellValue('Net'), DoubleCellValue(data.net)]);
    row(summary, [
      TextCellValue('Transactions'),
      IntCellValue(data.transactions.length),
    ]);

    final entries = excel['Transactions'];
    row(entries, [for (final h in _headers) TextCellValue(h)], header: true);
    for (final t in data.transactions) {
      row(entries, [
        TextCellValue(_dateTime.format(t.date)),
        TextCellValue(_type(t)),
        TextCellValue(t.categoryName),
        DoubleCellValue(t.amount),
        TextCellValue(t.paymentMethod ?? ''),
        TextCellValue(t.creditCardName ?? ''),
        TextCellValue(t.note ?? ''),
      ]);
    }

    if (defaultSheet != null && defaultSheet != 'Summary') {
      excel.delete(defaultSheet);
    }
    excel.setDefaultSheet('Summary');
    return Uint8List.fromList(excel.save()!);
  }

  /// A printable A4 report: title, period, totals, then every entry.
  ///
  /// Uses the PDF standard fonts, which cover Latin text only, so amounts are
  /// written with the currency code ("INR 1,200.00") rather than a symbol the
  /// font cannot draw, and other scripts in notes are replaced.
  static Future<Uint8List> buildPdf(ReportData data) async {
    final money = NumberFormat.currency(
      name: data.currency,
      symbol: '${data.currency} ',
      decimalDigits: 2,
    );
    final doc = pw.Document(
      title: 'Accounts Note report',
      author: 'Accounts Note',
    );
    final muted = const PdfColor.fromInt(0xFF64748B);
    final brand = const PdfColor.fromInt(0xFF1A6B6D);

    pw.Widget total(String label, double value, PdfColor color) => pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: const PdfColor.fromInt(0xFFE2E8F0)),
          borderRadius: pw.BorderRadius.circular(6),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(label, style: pw.TextStyle(fontSize: 9, color: muted)),
            pw.SizedBox(height: 4),
            pw.Text(
              money.format(value),
              style: pw.TextStyle(
                fontSize: 13,
                fontWeight: pw.FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Page ${context.pageNumber} of ${context.pagesCount}',
            style: pw.TextStyle(fontSize: 8, color: muted),
          ),
        ),
        build: (context) => [
          pw.Text(
            'Accounts Note report',
            style: pw.TextStyle(
              fontSize: 20,
              fontWeight: pw.FontWeight.bold,
              color: brand,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            pdfSafe(data.periodLabel),
            style: pw.TextStyle(fontSize: 11, color: muted),
          ),
          pw.SizedBox(height: 16),
          pw.Row(
            children: [
              total('Income', data.income, const PdfColor.fromInt(0xFF059669)),
              pw.SizedBox(width: 8),
              total(
                'Expenses',
                data.expense,
                const PdfColor.fromInt(0xFFE11D48),
              ),
              pw.SizedBox(width: 8),
              total(
                data.net >= 0 ? 'Net saved' : 'Net overspend',
                data.net.abs(),
                brand,
              ),
            ],
          ),
          pw.SizedBox(height: 20),
          pw.Text(
            '${data.transactions.length} transactions',
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),
          if (data.isEmpty)
            pw.Text(
              'Nothing was logged in this period.',
              style: pw.TextStyle(color: muted),
            )
          else
            pw.TableHelper.fromTextArray(
              headers: const ['Date', 'Type', 'Category', 'Amount', 'Note'],
              data: [
                for (final t in data.transactions)
                  [
                    DateFormat('d MMM yyyy').format(t.date),
                    _type(t),
                    pdfSafe(t.categoryName),
                    money.format(t.amount),
                    pdfSafe(
                      [
                        if (t.creditCardName != null) t.creditCardName!,
                        if (t.note != null && t.note!.isNotEmpty) t.note!,
                      ].join(' · '),
                    ),
                  ],
              ],
              headerStyle: pw.TextStyle(
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white,
              ),
              headerDecoration: pw.BoxDecoration(color: brand),
              cellStyle: const pw.TextStyle(fontSize: 9),
              cellAlignments: {3: pw.Alignment.centerRight},
              oddRowDecoration: const pw.BoxDecoration(
                color: PdfColor.fromInt(0xFFF4F7F8),
              ),
              border: null,
              columnWidths: {
                0: const pw.FixedColumnWidth(70),
                1: const pw.FixedColumnWidth(50),
                2: const pw.FlexColumnWidth(2),
                3: const pw.FixedColumnWidth(80),
                4: const pw.FlexColumnWidth(3),
              },
            ),
        ],
      ),
    );
    return doc.save();
  }

  /// Keeps what the PDF standard fonts can draw (Latin-1 and a few common
  /// punctuation marks); anything else becomes "?".
  static String pdfSafe(String text) {
    const extras = {
      0x2013,
      0x2014,
      0x2018,
      0x2019,
      0x201C,
      0x201D,
      0x2022,
      0x2026,
      0x20AC,
    };
    return String.fromCharCodes(
      text.runes.map((r) => r <= 0xFF || extras.contains(r) ? r : 0x3F),
    );
  }

  /// Writes the file and opens the share sheet (save to Files, Drive, email,
  /// WhatsApp…).
  static Future<void> share(ReportData data, ReportFormat format) async {
    final bytes = await build(data, format);
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/${data.fileName(format)}');
    await file.writeAsBytes(bytes, flush: true);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: format.mimeType)],
        text: 'Accounts Note report, ${data.periodLabel}',
      ),
    );
  }
}
