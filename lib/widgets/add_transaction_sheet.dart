import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/constants/app_constants.dart';
import '../core/theme/app_theme.dart';
import '../features/subscription/limit_reached_sheet.dart';
import '../providers/subscription_provider.dart';

/// Single entry point for "add a transaction" so every surface that offers it
/// (dashboard FAB, activity FAB) asks the same question the same way.
Future<void> showAddTransactionSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    builder: (sheetContext) => const _AddTransactionSheet(),
  );
}

class _AddTransactionSheet extends ConsumerWidget {
  const _AddTransactionSheet();

  /// Resolve the router before closing the sheet, so navigation never runs
  /// against a context that is on its way out of the tree.
  ///
  /// Checks today's allowance first: with it used up, the user is told so
  /// here rather than after filling in the whole form.
  Future<void> _open(
    BuildContext context,
    WidgetRef ref,
    TransactionType type,
  ) async {
    final router = GoRouter.of(context);
    final navigator = Navigator.of(context);
    final blocked = await ref.read(dailyLimitCheckerProvider).check(type);
    navigator.pop();
    if (blocked == null) {
      router.push('/transaction/add', extra: type);
      return;
    }
    final rootContext = router.routerDelegate.navigatorKey.currentContext;
    if (rootContext != null && rootContext.mounted) {
      await showDailyLimitReachedSheet(rootContext, blocked);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    // Scrollable because the form this opens autofocuses its amount field:
    // the keyboard rises while this sheet is still animating away, and the
    // shrunken space would otherwise overflow it for those frames.
    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            0,
            AppSpacing.xl,
            AppSpacing.xl,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('What would you like to add?', style: theme.textTheme.titleLarge),
              const SizedBox(height: AppSpacing.xl),
              _TypeOption(
                icon: Icons.south_west_rounded,
                color: AppColors.income,
                title: 'Income',
                subtitle: 'Salary, freelance, refunds…',
                onTap: () => _open(context, ref, TransactionType.income),
              ),
              const SizedBox(height: AppSpacing.md),
              _TypeOption(
                icon: Icons.north_east_rounded,
                color: AppColors.expense,
                title: 'Expense',
                subtitle: 'Food, travel, bills…',
                onTap: () => _open(context, ref, TransactionType.expense),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TypeOption extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _TypeOption({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadii.control),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.chevron_right_rounded,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
}
