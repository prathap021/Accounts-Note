import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../models/subscription_plan.dart';
import '../../providers/subscription_provider.dart';

/// Explains that today's allowance for one type is used up, and offers the
/// plans that raise it.
Future<void> showDailyLimitReachedSheet(
  BuildContext context,
  DailyLimitReached reached,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _LimitReachedSheet(reached: reached),
  );
}

class _LimitReachedSheet extends StatelessWidget {
  const _LimitReachedSheet({required this.reached});

  final DailyLimitReached reached;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final kind = reached.type == TransactionType.income ? 'income' : 'expense';
    final color = reached.type == TransactionType.income
        ? AppColors.income
        : AppColors.expense;
    final best = SubscriptionPlan.premium;
    final canUpgrade = reached.plan != best;
    final nextStep = canUpgrade
        ? 'Upgrade for up to ${best.limitFor(reached.type)} a day, or add '
              'more tomorrow.'
        : 'You can add more tomorrow.';

    return SafeArea(
      child: SingleChildScrollView(
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
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadii.control),
              ),
              child: Icon(Icons.hourglass_bottom_rounded, color: color),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Daily $kind limit reached',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              "You've added ${reached.limit} of ${reached.limit} $kind "
              'entries today on the ${reached.plan.title} plan. $nextStep',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Your allowance resets at midnight.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            if (canUpgrade)
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: const Icon(Icons.workspace_premium_rounded),
                  label: const Text('See plans'),
                  onPressed: () {
                    final router = GoRouter.of(context);
                    Navigator.pop(context);
                    router.push('/subscription');
                  },
                ),
              ),
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(canUpgrade ? 'Not now' : 'OK'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
