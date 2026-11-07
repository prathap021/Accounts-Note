import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart' hide Result;
import 'package:file_picker/file_picker.dart';
import 'package:csv/csv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/constants/app_constants.dart';
import '../../core/utils/result.dart';

/// One entry read from a CSV file.
class CsvEntry {
  const CsvEntry({
    required this.type,
    required this.amount,
    required this.date,
    required this.category,
    this.note,
    this.paymentMethod,
    this.account,
  });

  final TransactionType type;
  final double amount;
  final DateTime date;
  final String category;
  final String? note;
  final String? paymentMethod;
  final String? account;

  Map<String, Object?> toMap() => {
    'type': type.name,
    'amount': amount,
    'date': date.millisecondsSinceEpoch,
    'category': category,
    'note': note,
    'paymentMethod': paymentMethod,
    'account': account,
  };
}

/// What a CSV file holds, before anything is imported.
class CsvPreview {
  const CsvPreview({required this.entries, required this.skipped});

  final List<CsvEntry> entries;

  /// Data rows that could not be read (no date or amount).
  final int skipped;

  int get income =>
      entries.where((e) => e.type == TransactionType.income).length;
  int get expense => entries.length - income;

  DateTime? get first => entries.isEmpty
      ? null
      : entries.map((e) => e.date).reduce((a, b) => a.isBefore(b) ? a : b);
  DateTime? get last => entries.isEmpty
      ? null
      : entries.map((e) => e.date).reduce((a, b) => a.isAfter(b) ? a : b);
}

/// Why a file can't be imported.
class CsvFormatException implements Exception {
  const CsvFormatException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Reads CSV exports: this app's own report, other money apps and bank
/// statements. Columns are found by their header, in any order:
///
/// * a date (Date, Transaction date, Value date…), required;
/// * either an Amount (with a Type column, or negative for spending), or
///   separate Debit / Credit (Withdrawal / Deposit) columns;
/// * optionally Category, Note (Description, Narration…), Payment method
///   and Account.
class CsvImportParser {
  static const _dateHeaders = [
    'date',
    'transaction date',
    'txn date',
    'value date',
    'posting date',
    'date & time',
  ];
  static const _amountHeaders = ['amount', 'value', 'sum'];
  static const _typeHeaders = ['type', 'transaction type', 'dr/cr', 'cr/dr'];
  static const _debitHeaders = [
    'debit',
    'withdrawal',
    'withdrawals',
    'withdrawal amt.',
    'withdrawal amount',
    'debit amount',
    'expense',
  ];
  static const _creditHeaders = [
    'credit',
    'deposit',
    'deposits',
    'deposit amt.',
    'deposit amount',
    'credit amount',
    'income',
  ];
  static const _categoryHeaders = ['category', 'category name'];
  static const _noteHeaders = [
    'note',
    'notes',
    'description',
    'narration',
    'remarks',
    'details',
    'particulars',
    'memo',
  ];
  static const _paymentHeaders = ['payment method', 'payment', 'mode'];
  static const _accountHeaders = ['account', 'account name', 'wallet'];

  /// Day-first is tried before month-first: most of the world, and India,
  /// write 03/10/2026 for 3 October.
  static const _formats = [
    'yyyy-MM-dd HH:mm:ss',
    'yyyy-MM-dd HH:mm',
    'yyyy-MM-ddTHH:mm:ss',
    'yyyy-MM-dd',
    'yyyy/MM/dd',
    'dd/MM/yyyy HH:mm:ss',
    'dd/MM/yyyy HH:mm',
    'dd/MM/yyyy',
    'dd-MM-yyyy',
    'dd.MM.yyyy',
    'dd/MM/yy',
    'dd-MM-yy',
    'd MMM yyyy',
    'dd MMM yyyy',
    'd-MMM-yyyy',
    'dd-MMM-yyyy',
    'd-MMM-yy',
    'dd-MMM-yy',
    'MMM d, yyyy',
    'd MMM yyyy, h:mm a',
    'MMM d, yyyy · h:mm a',
  ];
  static final _parsers = {for (final f in _formats) f: DateFormat(f, 'en_US')};
  static final _yearFirst = RegExp(r'^\d{4}');

  static DateTime? parseDate(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;
    final iso = DateTime.tryParse(text);
    if (iso != null) return iso.isUtc ? iso.toLocal() : iso;
    for (final f in _formats) {
      // "03/10/26" must not be read as the year 3.
      if (f.startsWith('yyyy') && !_yearFirst.hasMatch(text)) continue;
      try {
        final d = _parsers[f]!.parseStrict(text);
        // Two-digit years: 26 means 2026, not 26 AD.
        return d.year < 100 ? DateTime(d.year + 2000, d.month, d.day) : d;
      } catch (_) {}
    }
    return null;
  }

  /// Reads "₹1,200.50", "1200" or "450.00 Dr". Commas are taken as
  /// thousands separators; "(450)", "-450" and a "Dr" suffix are negative.
  static double? parseAmount(String raw) {
    var text = raw.trim();
    if (text.isEmpty) return null;
    var negative = false;
    if (text.startsWith('(') && text.endsWith(')')) {
      negative = true;
      text = text.substring(1, text.length - 1);
    }
    final upper = text.toUpperCase();
    if (upper.endsWith('DR')) negative = true;
    text = text.replaceAll(RegExp(r'[^0-9.\-]'), '');
    if (text.startsWith('-')) {
      negative = true;
      text = text.substring(1);
    }
    final value = double.tryParse(text);
    if (value == null) return null;
    return negative ? -value : value;
  }

  static TransactionType? _typeFrom(String raw) {
    final t = raw.trim().toLowerCase();
    if (t.isEmpty) return null;
    if (['income', 'credit', 'cr', 'deposit', 'in', 'received'].contains(t)) {
      return TransactionType.income;
    }
    if ([
      'expense',
      'debit',
      'dr',
      'withdrawal',
      'out',
      'spent',
      'payment',
    ].contains(t)) {
      return TransactionType.expense;
    }
    return null;
  }

  static CsvPreview parse(String content) {
    final text = content.startsWith('﻿') ? content.substring(1) : content;
    final eol = text.contains('\r\n') ? '\r\n' : '\n';
    final rows = Csv(lineDelimiter: eol)
        .decode(text)
        .map((r) => r.map((c) => '${c ?? ''}').toList())
        .where((r) => r.any((c) => c.trim().isNotEmpty))
        .toList();
    if (rows.isEmpty) throw const CsvFormatException('The file is empty.');

    // The header is the first row naming a date column, so a bank's title
    // lines above the table are skipped.
    int? headerAt;
    for (var i = 0; i < rows.length && i < 30; i++) {
      final names = rows[i].map((c) => c.trim().toLowerCase()).toList();
      if (names.any(_dateHeaders.contains)) {
        headerAt = i;
        break;
      }
    }
    if (headerAt == null) {
      throw const CsvFormatException(
        'No Date column found. The first row should name the columns, '
        'such as Date, Amount, Type, Category and Note.',
      );
    }
    final header = rows[headerAt].map((c) => c.trim().toLowerCase()).toList();
    int? col(List<String> names) {
      for (final n in names) {
        final i = header.indexOf(n);
        if (i >= 0) return i;
      }
      return null;
    }

    final dateCol = col(_dateHeaders)!;
    final amountCol = col(_amountHeaders);
    final debitCol = col(_debitHeaders);
    final creditCol = col(_creditHeaders);
    if (amountCol == null && debitCol == null && creditCol == null) {
      throw const CsvFormatException(
        'No Amount column found (or Debit and Credit columns).',
      );
    }
    final typeCol = col(_typeHeaders);
    final categoryCol = col(_categoryHeaders);
    final noteCol = col(_noteHeaders);
    final paymentCol = col(_paymentHeaders);
    final accountCol = col(_accountHeaders);

    String cell(List<String> row, int? i) =>
        i == null || i >= row.length ? '' : row[i].trim();
    String? optional(List<String> row, int? i) {
      final v = cell(row, i);
      return v.isEmpty ? null : v;
    }

    // With no Type column, a minus sign marks spending; plus is income only
    // when the file uses minus signs at all.
    final signed =
        amountCol != null &&
        typeCol == null &&
        _hasNegatives(rows, headerAt, amountCol);

    final entries = <CsvEntry>[];
    var skipped = 0;
    for (final row in rows.skip(headerAt + 1)) {
      final date = parseDate(cell(row, dateCol));
      double? amount;
      TransactionType? type;
      if (debitCol != null || creditCol != null) {
        final debit = parseAmount(cell(row, debitCol))?.abs() ?? 0;
        final credit = parseAmount(cell(row, creditCol))?.abs() ?? 0;
        if (debit > 0) {
          amount = debit;
          type = TransactionType.expense;
        } else if (credit > 0) {
          amount = credit;
          type = TransactionType.income;
        }
      }
      if (amount == null && amountCol != null) {
        final value = parseAmount(cell(row, amountCol));
        if (value != null && value != 0) {
          amount = value.abs();
          type =
              _typeFrom(cell(row, typeCol)) ??
              (value < 0 || !signed
                  ? TransactionType.expense
                  : TransactionType.income);
        }
      }
      if (date == null || amount == null || type == null) {
        skipped++;
        continue;
      }
      entries.add(
        CsvEntry(
          type: type,
          amount: double.parse(amount.toStringAsFixed(2)),
          date: date,
          category: optional(row, categoryCol) ?? 'Other',
          note: optional(row, noteCol),
          paymentMethod: optional(row, paymentCol),
          account: optional(row, accountCol),
        ),
      );
    }
    if (entries.isEmpty) {
      throw CsvFormatException(
        'No entries could be read from the file ($skipped rows had no '
        'readable date or amount).',
      );
    }
    return CsvPreview(entries: entries, skipped: skipped);
  }

  /// A signed Amount column (no Type) uses minus for spending, so plus is
  /// income. Without any minus signs, every row is treated as spending.
  static bool _hasNegatives(List<List<String>> rows, int headerAt, int col) {
    for (final r in rows.skip(headerAt + 1)) {
      if (col < r.length && (parseAmount(r[col]) ?? 0) < 0) return true;
    }
    return false;
  }
}

/// What an import changed.
class CsvImportResult {
  const CsvImportResult({
    required this.added,
    required this.alreadyThere,
    required this.categoriesAdded,
    required this.remainingThisMonth,
  });

  final int added;
  final int alreadyThere;
  final int categoriesAdded;
  final int remainingThisMonth;

  factory CsvImportResult.fromMap(Map<Object?, Object?> m) {
    int n(String k) => (m[k] as num?)?.toInt() ?? 0;
    return CsvImportResult(
      added: n('added'),
      alreadyThere: n('alreadyThere'),
      categoriesAdded: n('categoriesAdded'),
      remainingThisMonth: n('remainingThisMonth'),
    );
  }
}

/// Sends the rows to the server, which writes them (see
/// functions/src/csvImport.ts for why it can't be done from the app).
abstract class CsvImportService {
  /// The text of a CSV file the user picks, or null if they cancel.
  Future<String?> pickFile();

  Future<Result<CsvImportResult>> importEntries(List<CsvEntry> entries);
}

class CloudCsvImportService implements CsvImportService {
  CloudCsvImportService({FirebaseFunctions? functions})
    : _functions =
          functions ?? FirebaseFunctions.instanceFor(region: 'us-central1');

  final FirebaseFunctions _functions;

  @override
  Future<String?> pickFile() async {
    final picked = await FilePicker.pickFile(dialogTitle: 'Choose a CSV file');
    if (picked == null) return null;
    return utf8.decode(await picked.readAsBytes(), allowMalformed: true);
  }

  @override
  Future<Result<CsvImportResult>> importEntries(List<CsvEntry> entries) async {
    try {
      final call = _functions.httpsCallable(
        'importCsvRows',
        options: HttpsCallableOptions(timeout: const Duration(minutes: 5)),
      );
      final res = await call.call<Map<Object?, Object?>>({
        'rows': [for (final e in entries) e.toMap()],
        'tzOffsetMinutes': DateTime.now().timeZoneOffset.inMinutes,
      });
      return Result.success(CsvImportResult.fromMap(res.data));
    } on FirebaseFunctionsException catch (e) {
      return Result.failure(
        AppFailure(
          e.message ?? 'The import failed. Please try again.',
          code: e.code,
        ),
      );
    } catch (e) {
      return Result.failure(AppFailure.fromException(e));
    }
  }
}

final csvImportServiceProvider = Provider<CsvImportService>(
  (ref) => CloudCsvImportService(),
);
