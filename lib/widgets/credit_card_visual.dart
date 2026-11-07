import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

/// Card colours on offer. Deep and saturated so white type on the preview
/// stays readable, and distinct enough to tell cards apart at swatch size.
const kCreditCardColors = <int>[
  0xFF1E3A8A, // navy
  0xFF279698, // brand teal
  0xFF047857, // emerald
  0xFF6D28D9, // violet
  0xFFBE123C, // crimson
  0xFFBE185D, // rose
  0xFFB45309, // bronze
  0xFF334155, // slate
];

LinearGradient _cardGradient(Color color) => LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [color, Color.lerp(color, Colors.black, 0.35)!],
    );

/// A card-shaped chip of colour: how a credit card is identified in lists,
/// pickers and filter chips, where an icon alone would not say which card.
class CreditCardSwatch extends StatelessWidget {
  final Color color;
  final double width;

  const CreditCardSwatch({super.key, required this.color, this.width = 40});

  @override
  Widget build(BuildContext context) {
    // Real cards are about 1.59:1.
    final height = width / 1.59;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        gradient: _cardGradient(color),
        borderRadius: BorderRadius.circular(width * 0.14),
      ),
      alignment: const Alignment(-0.55, -0.1),
      // The chip, so the swatch reads as a card rather than a coloured box.
      child: Container(
        width: width * 0.22,
        height: height * 0.26,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(width * 0.04),
        ),
      ),
    );
  }
}

/// Full-width preview of the card being added, so the name, number and colour
/// can be checked before saving.
class CreditCardPreview extends StatelessWidget {
  final String name;
  final String? last4;
  final Color color;
  final String? limitLabel;

  const CreditCardPreview({
    super.key,
    required this.name,
    required this.color,
    this.last4,
    this.limitLabel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const onCard = Colors.white;

    return Container(
      height: 150,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        gradient: _cardGradient(color),
        borderRadius: BorderRadius.circular(AppRadii.card),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.3),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.credit_card_rounded,
                color: onCard.withValues(alpha: 0.85),
              ),
              const Spacer(),
              if (limitLabel != null)
                Text(
                  limitLabel!,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: onCard.withValues(alpha: 0.85),
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
          const Spacer(),
          Text(
            '••••  ••••  ••••  ${last4 ?? '••••'}',
            style: theme.textTheme.titleMedium?.copyWith(
              color: onCard,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            name.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelLarge?.copyWith(
              color: onCard.withValues(alpha: 0.9),
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }
}
