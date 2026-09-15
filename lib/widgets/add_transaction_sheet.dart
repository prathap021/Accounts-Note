import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/constants/app_constants.dart';
import '../core/theme/app_theme.dart';

/// Single entry point for "add a transaction" so every surface that offers it
/// (dashboard FAB, activity FAB) asks the same question the same way.
Future<void> showAddTransactionSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    builder: (sheetContext) => const _AddTransactionSheet(),
  );
}

class _AddTransactionSheet extends StatelessWidget {
  const _AddTransactionSheet();

  /// Resolve the router before closing the sheet, so navigation never runs
  /// against a context that is on its way out of the tree.
  void _open(BuildContext context, TransactionType type) {
    final router = GoRouter.of(context);
    Navigator.pop(context);
    router.push('/transaction/add', extra: type);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
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
              onTap: () => _open(context, TransactionType.income),
            ),
            const SizedBox(height: AppSpacing.md),
            _TypeOption(
              icon: Icons.north_east_rounded,
              color: AppColors.expense,
              title: 'Expense',
              subtitle: 'Food, travel, bills…',
              onTap: () => _open(context, TransactionType.expense),
            ),
          ],
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
