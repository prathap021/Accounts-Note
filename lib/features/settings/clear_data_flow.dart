import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/snackbar_helper.dart';
import '../../data/repositories/data_reset_repository.dart';
import '../../providers/auth_provider.dart';
import '../../providers/sync_provider.dart';

/// "Clear all data", confirmed by typing DELETE.
Future<void> runClearAllData(BuildContext context, WidgetRef ref) async {
  final uid = ref.read(currentUidProvider);
  if (uid == null) return;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (_) => const _ConfirmClearDialog(),
  );
  if (confirmed != true || !context.mounted) return;

  final navigator = Navigator.of(context, rootNavigator: true);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    useRootNavigator: true,
    builder: (_) => const PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            SizedBox(width: AppSpacing.lg),
            Expanded(child: Text('Clearing your data…')),
          ],
        ),
      ),
    ),
  );

  // Stop syncing so nothing is re-uploaded while the cloud is emptied.
  final sync = ref.read(syncManagerProvider);
  await sync.stop();
  final result = await ref.read(dataResetRepositoryProvider).clearCloud(uid);
  if (result.isSuccess) {
    await ref.read(transactionLocalStoreProvider).clear();
  }
  await sync.start();
  if (navigator.canPop()) navigator.pop();
  if (!context.mounted) return;

  result.when(
    success: (_) => SnackbarHelper.showSuccess(
      context,
      'All your data was cleared. The default categories are back.',
    ),
    failure: (f) => SnackbarHelper.showError(context, f.userMessage),
  );
}

class _ConfirmClearDialog extends StatefulWidget {
  const _ConfirmClearDialog();

  @override
  State<_ConfirmClearDialog> createState() => _ConfirmClearDialogState();
}

class _ConfirmClearDialogState extends State<_ConfirmClearDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _typed => _controller.text.trim() == 'DELETE';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      icon: Icon(Icons.warning_amber_rounded, color: scheme.error),
      title: const Text('Clear all data?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Every transaction, category, card and budget is deleted from '
            'this phone and the cloud. Your account, subscription and '
            'settings stay. This cannot be undone, so back up first if you '
            'might want them later.',
          ),
          const SizedBox(height: AppSpacing.lg),
          TextField(
            controller: _controller,
            autocorrect: false,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(labelText: 'Type DELETE'),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: scheme.error,
            foregroundColor: scheme.onError,
          ),
          onPressed: _typed ? () => Navigator.pop(context, true) : null,
          child: const Text('Clear everything'),
        ),
      ],
    );
  }
}
