import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/sync/sync_manager.dart';
import '../core/theme/app_theme.dart';
import '../providers/sync_provider.dart';

/// Compact Synced / Syncing / Pending / Failed indicator.
///
/// Purely informational — it never blocks the user, and tapping it just asks
/// for another sync attempt.
class SyncStatusChip extends ConsumerWidget {
  const SyncStatusChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final state = ref.watch(currentSyncStateProvider);

    final (color, icon) = switch (state.phase) {
      SyncPhase.syncing => (scheme.primary, Icons.sync_rounded),
      SyncPhase.offline => (
          AppColors.warning,
          Icons.cloud_off_rounded,
        ),
      SyncPhase.failed => (AppColors.expense, Icons.error_outline_rounded),
      SyncPhase.idle => state.pendingCount > 0
          ? (AppColors.warning, Icons.cloud_upload_outlined)
          : (AppColors.income, Icons.cloud_done_outlined),
    };

    final count = state.pendingCount + state.failedCount;
    final label = count > 0 ? '${state.label} · $count' : state.label;

    return Tooltip(
      message: state.lastSyncedAt == null
          ? label
          : '$label · last synced ${TimeOfDay.fromDateTime(state.lastSyncedAt!).format(context)}',
      child: Material(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadii.pill),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => ref.read(syncManagerProvider).syncNow(),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: 7,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (state.phase == SyncPhase.syncing)
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: color,
                    ),
                  )
                else
                  Icon(icon, size: 14, color: color),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Banner shown above the Activity list when records could not be pushed, with
/// a one-tap retry. Absent entirely when everything is synced.
class SyncFailureBanner extends ConsumerWidget {
  const SyncFailureBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final state = ref.watch(currentSyncStateProvider);
    if (state.failedCount == 0) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: AppCard(
        color: AppColors.expense.withValues(alpha: 0.08),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline_rounded,
                color: AppColors.expense, size: 20),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                '${state.failedCount} ${state.failedCount == 1 ? 'entry' : 'entries'} '
                "couldn't sync. They are saved on this device.",
                style: theme.textTheme.bodySmall,
              ),
            ),
            TextButton(
              onPressed: () => ref.read(syncManagerProvider).retryFailed(),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                foregroundColor: AppColors.expense,
              ),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
