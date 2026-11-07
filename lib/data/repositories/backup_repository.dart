import 'dart:convert';
import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart' as cf;
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/utils/result.dart';

/// What a backup file holds, read on the device for the import preview.
class BackupPreview {
  final String? sourceEmail;
  final DateTime exportedAt;
  final String? currency;
  final int transactions;
  final int categories;
  final int creditCards;
  final int budgets;
  final DateTime? firstDate;
  final DateTime? lastDate;

  /// The file's text, sent as-is to the server, which checks its signature.
  final String content;

  const BackupPreview({
    required this.sourceEmail,
    required this.exportedAt,
    required this.currency,
    required this.transactions,
    required this.categories,
    required this.creditCards,
    required this.budgets,
    required this.firstDate,
    required this.lastDate,
    required this.content,
  });

  /// Reads [content]. Throws [FormatException] for anything that is not an
  /// Accounts Note backup. Whether the file is genuine and unchanged is for
  /// the server to decide; this only describes it.
  factory BackupPreview.parse(String content) {
    const notABackup = FormatException(
      'That is not an Accounts Note backup file.',
    );
    try {
      final file = jsonDecode(content) as Map<String, dynamic>;
      if (file['format'] != 'accounts-note-backup') throw notABackup;
      final payload =
          jsonDecode(utf8.decode(base64Decode(file['data'] as String)))
              as Map<String, dynamic>;
      final cols = payload['collections'] as Map<String, dynamic>;
      List<dynamic> list(String name) => (cols[name] as List?) ?? const [];

      DateTime? first;
      DateTime? last;
      for (final t in list('transactions')) {
        final ms = ((t as Map)['data'] as Map)['date'];
        if (ms is Map && ms['__ts'] is num) {
          final d = DateTime.fromMillisecondsSinceEpoch(
            (ms['__ts'] as num).toInt(),
          );
          if (first == null || d.isBefore(first)) first = d;
          if (last == null || d.isAfter(last)) last = d;
        }
      }

      return BackupPreview(
        sourceEmail: payload['sourceEmail'] as String?,
        exportedAt: DateTime.parse(payload['exportedAt'] as String).toLocal(),
        currency: payload['currency'] as String?,
        transactions: list('transactions').length,
        categories: list('categories').length,
        creditCards: list('creditCards').length,
        budgets: list('budgets').length,
        firstDate: first,
        lastDate: last,
        content: content,
      );
    } on FormatException {
      throw notABackup;
    } on TypeError {
      throw notABackup;
    }
  }
}

/// What an import changed.
class ImportSummary {
  final int transactionsAdded;
  final int transactionsAlreadyThere;
  final int categoriesAdded;
  final int creditCardsAdded;
  final int budgetsImported;

  const ImportSummary({
    required this.transactionsAdded,
    required this.transactionsAlreadyThere,
    required this.categoriesAdded,
    required this.creditCardsAdded,
    required this.budgetsImported,
  });

  factory ImportSummary.fromMap(Map<Object?, Object?> m) {
    int n(String k) => (m[k] as num?)?.toInt() ?? 0;
    return ImportSummary(
      transactionsAdded: n('transactionsAdded'),
      transactionsAlreadyThere: n('transactionsAlreadyThere'),
      categoriesAdded: n('categoriesAdded'),
      creditCardsAdded: n('creditCardsAdded'),
      budgetsImported: n('budgetsImported'),
    );
  }
}

/// Saving and picking backup files on the device: the share sheet and the
/// system file picker, behind an interface for tests.
abstract class BackupFiles {
  /// Offers the file to save or send (Files, Drive, email…).
  Future<void> share(String fileName, String content);

  /// The text of a file the user picks, or null if they cancel.
  Future<String?> pick();
}

class DeviceBackupFiles implements BackupFiles {
  const DeviceBackupFiles();

  @override
  Future<void> share(String fileName, String content) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$fileName');
    await file.writeAsString(content, flush: true);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'application/json')],
        text: 'Accounts Note backup',
      ),
    );
  }

  @override
  Future<String?> pick() async {
    final picked = await FilePicker.pickFile(
      dialogTitle: 'Choose an Accounts Note backup',
    );
    if (picked == null) return null;
    return utf8.decode(await picked.readAsBytes(), allowMalformed: true);
  }
}

/// Backups go through the server, which signs them on the way out and checks
/// the signature on the way in (see functions/src/backup.ts).
class BackupRepository {
  BackupRepository({cf.FirebaseFunctions? functions})
    : _functions =
          functions ?? cf.FirebaseFunctions.instanceFor(region: 'us-central1');

  final cf.FirebaseFunctions _functions;

  static const _timeout = Duration(minutes: 5);

  /// The signed backup file's text for the signed-in account.
  Future<Result<String>> create({required String currency}) async {
    try {
      final result = await _functions
          .httpsCallable(
            'createBackup',
            options: cf.HttpsCallableOptions(timeout: _timeout),
          )
          .call<Map<Object?, Object?>>({'currency': currency});
      return Result.success(result.data['content']! as String);
    } on cf.FirebaseFunctionsException catch (e) {
      return Result.failure(AppFailure(_message(e), code: e.code));
    } catch (e) {
      return Result.failure(
        const AppFailure(
          'Could not reach the server. Check your connection and try again.',
          code: 'unavailable',
        ),
      );
    }
  }

  /// Adds the backup's contents to the signed-in account.
  Future<Result<ImportSummary>> importContent(String content) async {
    try {
      final result = await _functions
          .httpsCallable(
            'importBackup',
            options: cf.HttpsCallableOptions(timeout: _timeout),
          )
          .call<Map<Object?, Object?>>({'content': content});
      return Result.success(ImportSummary.fromMap(result.data));
    } on cf.FirebaseFunctionsException catch (e) {
      return Result.failure(AppFailure(_message(e), code: e.code));
    } catch (e) {
      return Result.failure(
        const AppFailure(
          'Could not reach the server. Check your connection and try again.',
          code: 'unavailable',
        ),
      );
    }
  }

  static String _message(cf.FirebaseFunctionsException e) {
    final m = e.message?.trim();
    if (m != null && m.isNotEmpty && e.code != 'internal') return m;
    return 'Something went wrong with the backup. Please try again.';
  }

  /// e.g. `accounts_note_backup_2026-11-07.json`.
  static String fileName([DateTime? now]) =>
      'accounts_note_backup_'
      '${DateFormat('yyyy-MM-dd').format(now ?? DateTime.now())}.json';
}

final backupRepositoryProvider = Provider<BackupRepository>((ref) {
  return BackupRepository();
});

final backupFilesProvider = Provider<BackupFiles>((ref) {
  return const DeviceBackupFiles();
});
