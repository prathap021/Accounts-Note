import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';

enum ContributionPromptResult { notNow, contribute }

/// Optional contribution dialog — never blocks income/expense tracking.
Future<ContributionPromptResult?> showContributionPromptDialog(
  BuildContext context,
) {
  final threshold = AppDefaults.contributionPromptTransactionThreshold;
  return showDialog<ContributionPromptResult>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) {
      final scheme = Theme.of(ctx).colorScheme;
      return AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        icon: CircleAvatar(
          radius: 28,
          backgroundColor: AppColors.brandSoft,
          child: Icon(Icons.favorite_rounded, color: scheme.primary, size: 28),
        ),
        title: const Text('Support Accounts Note?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'You\'ve added $threshold income & expense transactions. '
              'If you\'d like, you can make an optional contribution to support the app.',
              style: Theme.of(ctx).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            Text(
              'Contribution is completely optional and separate from your '
              'income and expense tracking. You can keep adding transactions normally either way.',
              style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.pop(ctx, ContributionPromptResult.notNow),
            child: const Text('Not Now'),
          ),
          FilledButton.icon(
            onPressed: () =>
                Navigator.pop(ctx, ContributionPromptResult.contribute),
            icon: const Icon(Icons.favorite_rounded, size: 18),
            label: const Text('Contribute'),
          ),
        ],
      );
    },
  );
}

/// Shown after a successful contribution payment.
Future<void> showContributionThankYouDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (ctx) {
      final scheme = Theme.of(ctx).colorScheme;
      return AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        icon: const CircleAvatar(
          radius: 28,
          backgroundColor: AppColors.brandSoft,
          child: Icon(Icons.check_circle_rounded,
              color: AppColors.income, size: 30),
        ),
        title: const Text('Thank you for contributing!'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'You\'re marked as a contributor on your profile. '
              'Your gift is not recorded as an income or expense transaction.',
              style: Theme.of(ctx).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            Text(
              'We won\'t ask again this month. You can keep adding income and '
              'expense transactions normally anytime.',
              style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Continue'),
          ),
        ],
      );
    },
  );
}
