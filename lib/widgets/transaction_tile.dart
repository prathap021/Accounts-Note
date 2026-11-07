import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/constants/app_constants.dart';
import '../core/constants/category_icons.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/responsive.dart';
import '../core/utils/currency_formatter.dart';
import '../models/category_model.dart';
import '../models/credit_card_model.dart';
import '../models/transaction_model.dart';

class TransactionTile extends StatelessWidget {
  final TransactionModel transaction;
  final String currency;

  /// The transaction's category, when it could be resolved. Supplies the row
  /// icon and colour; a missing category falls back to a direction arrow.
  final CategoryModel? category;

  /// The card this was charged to, when it still exists. Its current name
  /// wins over the one stored on the transaction, so a rename shows at once.
  final CreditCardModel? creditCard;

  final VoidCallback? onTap;
  final VoidCallback? onDelete;

  /// Swipe right to edit.
  final VoidCallback? onEdit;

  /// Grouped lists already print the day above the row, so they turn the date
  /// off and the meta line shows just the time.
  final bool showDate;

  const TransactionTile({
    super.key,
    required this.transaction,
    this.currency = 'INR',
    this.category,
    this.creditCard,
    this.onTap,
    this.onDelete,
    this.onEdit,
    this.showDate = true,
  });

  bool get _isIncome => transaction.type == TransactionType.income;

  /// Time / date plus how it was paid — the quiet third line. A card charge
  /// names the card rather than the generic "Credit Card".
  String _metaLine() {
    final payment = creditCard?.displayName ??
        transaction.creditCardName ??
        transaction.paymentMethod;
    final account = transaction.isOnCard ? null : transaction.accountName;
    final parts = <String>[
      if (showDate)
        DateFormat('MMM d, yyyy · h:mm a').format(transaction.date)
      else
        DateFormat('h:mm a').format(transaction.date),
      if (payment != null && payment.isNotEmpty) payment,
      if (account != null && account.isNotEmpty) account,
      if (transaction.hasReceipt) 'Receipt',
    ];
    return parts.join('  ·  ');
  }

  Future<bool> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this transaction?'),
        content: Text(
          '${transaction.categoryName} · '
          '${CurrencyFormatter.format(transaction.amount, currencyCode: currency)}'
          '\n\nYou can undo this for a few seconds afterwards.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final amountColor = _isIncome ? AppColors.income : AppColors.expense;
    final sign = _isIncome ? '+' : '−';
    final note = transaction.note?.trim();
    final hasNote = note != null && note.isNotEmpty;

    return Dismissible(
      key: ValueKey(transaction.id),
      direction: switch ((onEdit != null, onDelete != null)) {
        (true, true) => DismissDirection.horizontal,
        (false, true) => DismissDirection.endToStart,
        (true, false) => DismissDirection.startToEnd,
        _ => DismissDirection.none,
      },
      // Swipe right: edit.
      background: Container(
        alignment: Alignment.centerLeft,
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.only(left: AppSpacing.xl),
        decoration: BoxDecoration(
          color: scheme.primaryContainer,
          borderRadius: BorderRadius.circular(AppRadii.card),
        ),
        child: Row(
          children: [
            Icon(Icons.edit_outlined, color: scheme.onPrimaryContainer),
            const SizedBox(width: AppSpacing.sm),
            Text(
              'Edit',
              style: theme.textTheme.labelLarge?.copyWith(
                color: scheme.onPrimaryContainer,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
      // Swipe left: delete.
      secondaryBackground: Container(
        alignment: Alignment.centerRight,
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.only(right: AppSpacing.xl),
        decoration: BoxDecoration(
          color: scheme.errorContainer,
          borderRadius: BorderRadius.circular(AppRadii.card),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Icon(Icons.delete_outline_rounded, color: scheme.onErrorContainer),
            const SizedBox(width: AppSpacing.sm),
            Text(
              'Delete',
              style: theme.textTheme.labelLarge?.copyWith(
                color: scheme.onErrorContainer,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
      // Swiping is easy to do by accident on a ledger — always ask first.
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          onEdit?.call();
          return false; // The row stays; the editor opens.
        }
        return _confirmDelete(context);
      },
      onDismissed: (_) => onDelete?.call(),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadii.card),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.md,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _CategoryAvatar(
                  category: category,
                  isIncome: _isIncome,
                  fallbackColor: amountColor,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Name and amount share the top line; the description
                      // below then gets the row's full width.
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              transaction.categoryName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Text(
                            '$sign${CurrencyFormatter.format(transaction.amount, currencyCode: currency)}',
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: amountColor,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                      if (hasNote) ...[
                        const SizedBox(height: 3),
                        Text(
                          note,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurface.withValues(alpha: 0.75),
                            height: 1.35,
                          ),
                        ),
                      ],
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _metaLine(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          if (transaction.pendingSync) ...[
                            const SizedBox(width: AppSpacing.sm),
                            Icon(
                              Icons.cloud_sync_outlined,
                              size: 12.rr,
                              color: scheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              'Syncing',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
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

/// Category icon in the category's own colour, with a small corner badge
/// showing whether money came in or went out.
class _CategoryAvatar extends StatelessWidget {
  final CategoryModel? category;
  final bool isIncome;
  final Color fallbackColor;

  const _CategoryAvatar({
    required this.category,
    required this.isIncome,
    required this.fallbackColor,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color =
        category != null ? categoryColor(category!.color) : fallbackColor;
    final icon = category != null
        ? iconFor(category!.icon)
        : (isIncome ? Icons.south_west_rounded : Icons.north_east_rounded);
    final badgeColor = isIncome ? AppColors.income : AppColors.expense;

    return SizedBox(
      width: 46.rr,
      height: 46.rr,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 44.rr,
            height: 44.rr,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(14.rr),
            ),
            child: Icon(icon, color: color, size: 21.rr),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 17.rr,
              height: 17.rr,
              decoration: BoxDecoration(
                color: badgeColor,
                shape: BoxShape.circle,
                // Ring in the surface colour so the badge reads as separate
                // from the tile behind it.
                border: Border.all(color: scheme.surfaceContainer, width: 2.rr),
              ),
              child: Icon(
                isIncome
                    ? Icons.south_west_rounded
                    : Icons.north_east_rounded,
                size: 9.rr,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
