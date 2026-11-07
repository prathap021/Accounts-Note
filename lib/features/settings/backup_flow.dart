import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/constants/currencies.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/snackbar_helper.dart';
import '../../data/repositories/csv_import_repository.dart';
import '../../data/repositories/backup_repository.dart';
import '../../providers/auth_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/sync_provider.dart';

final _count = NumberFormat.decimalPattern();
final _day = DateFormat('d MMM yyyy');

/// "Back up now": everything in this account, in one signed file the user
/// saves or sends wherever they like.
Future<void> runBackup(BuildContext context, WidgetRef ref) async {
  // The backup is made from the cloud copy, so push anything still queued
  // on this device first, and say so if some of it cannot go yet.
  final sync = ref.read(syncManagerProvider);
  if (await sync.isOnline()) await sync.syncNow();
  final pending = ref.read(transactionLocalStoreProvider).pendingCount;
  if (!context.mounted) return;
  if (pending > 0) {
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Some entries are not synced yet'),
        content: Text(
          '${_count.format(pending)} '
          '${pending == 1 ? 'entry has' : 'entries have'} not reached the '
          "cloud yet, so ${pending == 1 ? 'it' : 'they'} won't be in this "
          'backup. Connect to the internet to include '
          "${pending == 1 ? 'it' : 'them'}.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Back up anyway'),
          ),
        ],
      ),
    );
    if (go != true || !context.mounted) return;
  }

  final currency = ref.read(settingsProvider).currency;
  final close = _showProgress(context, 'Creating your backup…');
  final result = await ref
      .read(backupRepositoryProvider)
      .create(currency: currency);
  close();
  if (!context.mounted) return;

  await result.when(
    success: (content) async {
      final count = BackupPreview.parse(content).transactions;
      await ref
          .read(backupFilesProvider)
          .share(BackupRepository.fileName(), content);
      if (context.mounted) {
        SnackbarHelper.showSuccess(
          context,
          'Backup ready with ${_count.format(count)} '
          '${count == 1 ? 'transaction' : 'transactions'}.',
        );
      }
    },
    failure: (f) async => SnackbarHelper.showError(context, f.userMessage),
  );
}

/// "Import a backup": adds a backup's contents to this account, whichever
/// account it came from.
Future<void> runImport(BuildContext context, WidgetRef ref) async {
  final content = await ref.read(backupFilesProvider).pick();
  if (content == null || !context.mounted) return;

  final BackupPreview preview;
  try {
    preview = BackupPreview.parse(content);
  } on FormatException catch (e) {
    SnackbarHelper.showError(context, e.message);
    return;
  }

  final current = ref.read(settingsProvider).currency;
  final choice = await showDialog<_ImportChoice>(
    context: context,
    builder: (_) => _ImportPreviewDialog(
      preview: preview,
      currentCurrency: current,
      targetEmail: ref.read(authStateProvider).asData?.value?.email,
    ),
  );
  if (choice == null || !context.mounted) return;

  final close = _showProgress(context, 'Importing your backup…');
  final result = await ref
      .read(backupRepositoryProvider)
      .importContent(preview.content);
  if (result.isSuccess) {
    if (choice.switchCurrency && preview.currency != null) {
      await ref.read(settingsProvider.notifier).setCurrency(preview.currency!);
    }
    // Bring the imported entries down to this device straight away.
    await ref.read(syncManagerProvider).syncNow();
  }
  close();
  if (!context.mounted) return;

  result.when(
    success: (s) {
      final skipped = s.transactionsAlreadyThere;
      SnackbarHelper.showSuccess(
        context,
        'Imported ${_count.format(s.transactionsAdded)} '
        '${s.transactionsAdded == 1 ? 'transaction' : 'transactions'}'
        '${skipped > 0 ? ' (${_count.format(skipped)} already here)' : ''}.',
      );
    },
    failure: (f) => SnackbarHelper.showError(context, f.userMessage),
  );
}

/// A blocking "working…" dialog. Returns the function that closes it.
VoidCallback _showProgress(BuildContext context, String message) {
  final navigator = Navigator.of(context, rootNavigator: true);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    useRootNavigator: true,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          children: [
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            const SizedBox(width: AppSpacing.lg),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    ),
  );
  return () {
    if (navigator.canPop()) navigator.pop();
  };
}

class _ImportChoice {
  final bool switchCurrency;
  const _ImportChoice({required this.switchCurrency});
}

class _ImportPreviewDialog extends StatefulWidget {
  const _ImportPreviewDialog({
    required this.preview,
    required this.currentCurrency,
    required this.targetEmail,
  });

  final BackupPreview preview;
  final String currentCurrency;
  final String? targetEmail;

  @override
  State<_ImportPreviewDialog> createState() => _ImportPreviewDialogState();
}

class _ImportPreviewDialogState extends State<_ImportPreviewDialog> {
  late bool _switchCurrency = _currencyDiffers;

  bool get _currencyDiffers =>
      widget.preview.currency != null &&
      widget.preview.currency != widget.currentCurrency;

  String _currencyName(String code) {
    final c = currencyByCode(code);
    return c == null ? code : '${c.name} (${c.symbol.trim()})';
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.preview;
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final range = p.firstDate == null
        ? null
        : '${_day.format(p.firstDate!)} – ${_day.format(p.lastDate!)}';

    return AlertDialog(
      title: const Text('Import this backup?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Made ${_day.format(p.exportedAt)}'
              '${p.sourceEmail == null ? '' : ' from ${p.sourceEmail}'}.',
              style: muted,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              '${_count.format(p.transactions)} '
              '${p.transactions == 1 ? 'transaction' : 'transactions'}',
              style: theme.textTheme.titleMedium,
            ),
            if (range != null) Text(range, style: muted),
            const SizedBox(height: AppSpacing.sm),
            Text(
              '${_count.format(p.categories)} categories · '
              '${_count.format(p.creditCards)} '
              '${p.creditCards == 1 ? 'card' : 'cards'} · '
              '${_count.format(p.budgets)} '
              '${p.budgets == 1 ? 'budget' : 'budgets'}',
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Everything is added to this account'
              '${widget.targetEmail == null ? '' : ' (${widget.targetEmail})'}'
              '. Matching categories and cards are reused, entries already '
              "here are skipped, and importing doesn't use up today's "
              'allowance.',
              style: muted,
            ),
            if (_currencyDiffers) ...[
              const SizedBox(height: AppSpacing.sm),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _switchCurrency,
                onChanged: (v) => setState(() => _switchCurrency = v ?? false),
                title: Text('Switch the app to ${_currencyName(p.currency!)}'),
                subtitle: Text(
                  'The backup is in ${p.currency}; the app is set to '
                  '${widget.currentCurrency}.',
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            _ImportChoice(switchCurrency: _currencyDiffers && _switchCurrency),
          ),
          child: const Text('Import'),
        ),
      ],
    );
  }
}

/// "Import from CSV": entries from another app, a bank statement or this
/// app's own report, after a preview of what the file holds.
Future<void> runCsvImport(BuildContext context, WidgetRef ref) async {
  final service = ref.read(csvImportServiceProvider);
  final content = await service.pickFile();
  if (content == null || !context.mounted) return;

  final CsvPreview preview;
  try {
    preview = CsvImportParser.parse(content);
  } on CsvFormatException catch (e) {
    SnackbarHelper.showError(context, e.message);
    return;
  } catch (_) {
    SnackbarHelper.showError(context, "That file isn't a CSV file we can read.");
    return;
  }

  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(
        'Import ${_count.format(preview.entries.length)} '
        '${preview.entries.length == 1 ? 'entry' : 'entries'}?',
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${_count.format(preview.income)} income · '
            '${_count.format(preview.expense)} expense',
            key: const Key('csv-preview-counts'),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'From ${_day.format(preview.first!)} to ${_day.format(preview.last!)}',
          ),
          if (preview.skipped > 0) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              '${_count.format(preview.skipped)} '
              '${preview.skipped == 1 ? 'row has' : 'rows have'} no readable '
              'date or amount and will be left out.',
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          Text(
            'Categories are matched by name, and new names are added. '
            'Importing the same file again adds nothing twice.',
            style: Theme.of(ctx).textTheme.bodySmall,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Import'),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;

  final close = _showProgress(context, 'Importing your entries…');
  final result = await service.importEntries(preview.entries);
  if (result.isSuccess) await ref.read(syncManagerProvider).syncNow();
  close();
  if (!context.mounted) return;
  result.when(
    success: (r) => SnackbarHelper.showSuccess(
      context,
      'Imported ${_count.format(r.added)} '
      '${r.added == 1 ? 'entry' : 'entries'}'
      '${r.alreadyThere > 0 ? ' (${_count.format(r.alreadyThere)} already here)' : ''}.',
    ),
    failure: (f) => SnackbarHelper.showError(context, f.userMessage),
  );
}
