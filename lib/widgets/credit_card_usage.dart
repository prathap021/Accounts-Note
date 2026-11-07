import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../core/utils/currency_formatter.dart';
import '../models/credit_card_model.dart';
import 'credit_card_visual.dart';

/// How much of [limit] has been used, from 0 to 1, or null when the card has
/// no limit set.
///
/// Clamped at 1 so the bar cannot run past its track, but [CreditCardUsageTile]
/// still reports the real overspend in words — a bar pinned at full would
/// otherwise read the same at 100% and at 300%.
double? creditCardUtilisation(double spent, double? limit) {
  if (limit == null || limit <= 0) return null;
  final ratio = spent / limit;
  return ratio.clamp(0.0, 1.0).toDouble();
}

/// One card's month: what has been charged to it, against its limit.
///
/// Deliberately not a cash figure. This spend never touched the user's
/// balance — it is what the issuer will bill — so it is shown on its own
/// terms, with the headroom left rather than a running total.
class CreditCardUsageTile extends StatelessWidget {
  final CreditCardModel card;
  final double spent;
  final String currency;
  final VoidCallback? onTap;

  const CreditCardUsageTile({
    super.key,
    required this.card,
    required this.spent,
    required this.currency,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final cardColor = Color(card.color);

    final limit = card.creditLimit;
    final ratio = creditCardUtilisation(spent, limit);
    final remaining = limit == null ? null : limit - spent;
    final overLimit = remaining != null && remaining < 0;

    String money(double value) =>
        CurrencyFormatter.format(value, currencyCode: currency);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.card),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CreditCardSwatch(color: cardColor, width: 38),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        card.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        limit == null
                            ? 'No limit set'
                            : 'of ${money(limit)} limit',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  money(spent),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: overLimit ? AppColors.expense : scheme.onSurface,
                  ),
                ),
              ],
            ),
            if (ratio != null) ...[
              const SizedBox(height: AppSpacing.sm),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: ratio,
                  minHeight: 6,
                  backgroundColor: scheme.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    overLimit ? AppColors.expense : cardColor,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                overLimit
                    ? '${money(-remaining)} over the limit'
                    : '${money(remaining!)} left',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: overLimit
                      ? AppColors.expense
                      : scheme.onSurfaceVariant,
                  fontWeight: overLimit ? FontWeight.w700 : null,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
