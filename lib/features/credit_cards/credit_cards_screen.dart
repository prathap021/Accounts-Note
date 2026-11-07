import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/utils/result.dart';
import '../../core/utils/snackbar_helper.dart';
import '../../data/repositories/transaction_repository.dart';
import '../../models/credit_card_model.dart';
import '../../providers/credit_card_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/transaction_provider.dart';
import '../../widgets/credit_card_visual.dart';

/// Opens the add/edit card form. Completes with the saved card, or null if the
/// user backed out — so a picker can select a card the moment it is created.
Future<CreditCardModel?> showCreditCardForm(
  BuildContext context, {
  CreditCardModel? existing,
}) {
  return showModalBottomSheet<CreditCardModel>(
    context: context,
    isScrollControlled: true,
    // With the keyboard up the form reaches the top; keep it below the
    // status bar.
    useSafeArea: true,
    builder: (_) => _CreditCardFormSheet(existing: existing),
  );
}

/// Shows Activity narrowed to [filter], where the list and its total live.
void _openActivity(
  BuildContext context,
  WidgetRef ref,
  TransactionFilter filter,
) {
  ref.read(transactionFilterProvider.notifier).update(filter);
  context.go('/transactions');
}

class CreditCardsScreen extends ConsumerWidget {
  const CreditCardsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cardsAsync = ref.watch(creditCardsStreamProvider);
    final spend = ref.watch(creditCardSpendProvider);
    final currency = ref.watch(settingsProvider).currency;
    // The empty state carries its own Add button; one is enough.
    final hasCards = cardsAsync.asData?.value.isNotEmpty ?? false;

    return Scaffold(
      appBar: AppBar(title: const Text('Credit cards')),
      floatingActionButton: hasCards
          ? FloatingActionButton.extended(
              heroTag: 'fab-credit-cards',
              onPressed: () => showCreditCardForm(context),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add card'),
            )
          : null,
      body: cardsAsync.when(
        data: (cards) {
          if (cards.isEmpty) {
            // Scrollable so it does not overflow when the add-card sheet's
            // keyboard shrinks the screen behind it.
            return Center(
              child: SingleChildScrollView(
                child: EmptyState(
                  icon: Icons.credit_card_rounded,
                  title: 'No credit cards yet',
                  message:
                      'Add the cards you pay with, then choose one as the '
                      'payment method when you log an expense to see what '
                      'each card has spent.',
                  actionLabel: 'Add card',
                  onAction: () => showCreditCardForm(context),
                ),
              ),
            );
          }

          // Every card's spend, including cards since deleted, so this
          // matches the "All cards" total that tapping it opens.
          final monthTotal =
              spend.values.fold<double>(0, (sum, v) => sum + v);

          return ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.gutter,
              AppSpacing.sm,
              AppSpacing.gutter,
              AppSpacing.scrollBottom,
            ),
            children: [
              _MonthTotalCard(total: monthTotal, currency: currency),
              const SizedBox(height: AppSpacing.xl),
              const SectionLabel('Your cards'),
              for (final card in cards) ...[
                _CardRow(
                  card: card,
                  spent: spend[card.id] ?? 0,
                  currency: currency,
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
            ],
          );
        },
        loading: () => ListView(
          padding: const EdgeInsets.all(AppSpacing.gutter),
          children: const [
            SkeletonBox(height: 104, radius: AppRadii.card),
            SizedBox(height: AppSpacing.xl),
            SkeletonBox(height: 72, radius: AppRadii.card),
            SizedBox(height: AppSpacing.sm),
            SkeletonBox(height: 72, radius: AppRadii.card),
          ],
        ),
        error: (e, _) => Padding(
          padding: const EdgeInsets.all(AppSpacing.gutter),
          child: Center(
            child: AppErrorState(
              message: "We couldn't load your credit cards.",
              onRetry: () => ref.invalidate(creditCardsStreamProvider),
            ),
          ),
        ),
      ),
    );
  }
}

/// This month across every card. Tapping it lists the entries behind it.
class _MonthTotalCard extends ConsumerWidget {
  final double total;
  final String currency;

  const _MonthTotalCard({required this.total, required this.currency});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final now = DateTime.now();
    final month = monthRangeFor(now);

    return AppCard(
      elevated: true,
      padding: const EdgeInsets.all(AppSpacing.xl),
      onTap: () => _openActivity(
        context,
        ref,
        TransactionFilter(
          paymentMethod: kCreditCardPaymentMethod,
          startDate: month.start,
          endDate: month.end,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SPENT ON CARDS · ${DateFormat('MMMM').format(now).toUpperCase()}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    CurrencyFormatter.format(total, currencyCode: currency),
                    maxLines: 1,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Tap here, or on a card, to see what makes up the total.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
        ],
      ),
    );
  }
}

enum _CardAction { edit, delete }

class _CardRow extends ConsumerWidget {
  final CreditCardModel card;
  final double spent;
  final String currency;

  const _CardRow({
    required this.card,
    required this.spent,
    required this.currency,
  });

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "${card.name}"?'),
        content: const Text(
          'Expenses already marked on this card stay in your ledger and keep '
          "its name, but you won't be able to pick it or filter by it any more.",
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
    if (confirmed != true) return;
    final ok =
        await ref.read(creditCardActionsProvider.notifier).deleteCard(card.id);
    if (!ok && context.mounted) {
      SnackbarHelper.showError(context, "Couldn't delete this card.");
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = Color(card.color);
    final limit = card.creditLimit;
    final usage = limit == null || limit <= 0 ? null : spent / limit;
    final usageColor = usage == null || usage < 0.8
        ? color
        : usage > 1
            ? AppColors.expense
            : AppColors.warning;

    return AppCard(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.xs,
        AppSpacing.md,
      ),
      onTap: () {
        final month = monthRangeFor(DateTime.now());
        _openActivity(
          context,
          ref,
          TransactionFilter(
            creditCardId: card.id,
            startDate: month.start,
            endDate: month.end,
          ),
        );
      },
      child: Column(
        children: [
          Row(
            children: [
              CreditCardSwatch(color: color, width: 44),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      card.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      card.last4 == null ? 'Credit card' : '•••• ${card.last4}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    CurrencyFormatter.format(spent, currencyCode: currency),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'this month',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              PopupMenuButton<_CardAction>(
                tooltip: 'Card options',
                icon: Icon(
                  Icons.more_vert_rounded,
                  color: scheme.onSurfaceVariant,
                ),
                onSelected: (action) {
                  switch (action) {
                    case _CardAction.edit:
                      showCreditCardForm(context, existing: card);
                    case _CardAction.delete:
                      _confirmDelete(context, ref);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: _CardAction.edit,
                    child: ListTile(
                      leading: Icon(Icons.edit_outlined),
                      title: Text('Edit'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  PopupMenuItem(
                    value: _CardAction.delete,
                    child: ListTile(
                      leading: Icon(Icons.delete_outline_rounded),
                      title: Text('Delete'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (usage != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                    child: LinearProgressIndicator(
                      value: usage.clamp(0.0, 1.0),
                      minHeight: 6,
                      backgroundColor: scheme.surfaceContainerHighest,
                      color: usageColor,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    '${(usage * 100).round()}% of '
                    '${CurrencyFormatter.formatCompact(limit!, currencyCode: currency)} '
                    'limit used this month',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: usage > 1
                          ? AppColors.expense
                          : scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CreditCardFormSheet extends ConsumerStatefulWidget {
  final CreditCardModel? existing;
  const _CreditCardFormSheet({this.existing});

  @override
  ConsumerState<_CreditCardFormSheet> createState() =>
      _CreditCardFormSheetState();
}

class _CreditCardFormSheetState extends ConsumerState<_CreditCardFormSheet> {
  final _nameController = TextEditingController();
  final _last4Controller = TextEditingController();
  final _limitController = TextEditingController();
  int _color = kCreditCardColors.first;
  String? _nameError;
  String? _last4Error;
  String? _limitError;
  String? _saveError;
  bool _saving = false;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      _nameController.text = existing.name;
      _last4Controller.text = existing.last4 ?? '';
      final limit = existing.creditLimit;
      if (limit != null) {
        _limitController.text = limit == limit.roundToDouble()
            ? limit.toStringAsFixed(0)
            : limit.toStringAsFixed(2);
      }
      _color = existing.color;
    }
    // The preview tracks every keystroke.
    for (final c in [_nameController, _last4Controller, _limitController]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _last4Controller.dispose();
    _limitController.dispose();
    super.dispose();
  }

  double? get _limit =>
      double.tryParse(_limitController.text.trim().replaceAll(',', ''));

  Future<void> _save() async {
    final name = _nameController.text.trim();
    final last4 = _last4Controller.text.trim();
    final limitText = _limitController.text.trim();
    final limit = _limit;

    setState(() {
      _nameError = name.isEmpty
          ? 'Give this card a name'
          : CreditCardModel.containsCardNumber(name)
              ? 'Leave the card number out — only the last 4 digits are kept'
              : null;
      _last4Error = last4.isEmpty || CreditCardModel.isValidLast4(last4)
          ? null
          : 'Enter exactly 4 digits';
      _limitError = limitText.isEmpty ||
              (limit != null &&
                  limit > 0 &&
                  limit < CreditCardModel.maxCreditLimit)
          ? null
          : 'Enter a valid amount';
      _saveError = null;
    });
    if (_nameError != null || _last4Error != null || _limitError != null) {
      return;
    }

    setState(() => _saving = true);
    final notifier = ref.read(creditCardActionsProvider.notifier);
    final navigator = Navigator.of(context);

    CreditCardModel? saved;
    final existing = widget.existing;
    if (existing == null) {
      saved = await notifier.addCard(CreditCardModel(
        id: '',
        name: name,
        last4: last4.isEmpty ? null : last4,
        color: _color,
        creditLimit: limit,
        createdAt: DateTime.now(),
      ));
    } else {
      final updated = existing.copyWith(
        name: name,
        last4: last4.isEmpty ? null : last4,
        clearLast4: last4.isEmpty,
        color: _color,
        creditLimit: limit,
        clearCreditLimit: limit == null,
      );
      saved = await notifier.updateCard(updated) ? updated : null;
    }

    if (!mounted) return;
    if (saved == null) {
      // Shown in the sheet: a snackbar would land behind it.
      final state = ref.read(creditCardActionsProvider);
      final failure = state is AsyncError && state.error is AppFailure
          ? state.error as AppFailure
          : null;
      setState(() {
        _saving = false;
        _saveError =
            failure?.userMessage ?? 'Something went wrong. Please try again.';
      });
      return;
    }
    navigator.pop(saved);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final currency = ref.watch(settingsProvider).currency;
    final name = _nameController.text.trim();
    final last4 = _last4Controller.text.trim();
    final limit = _limit;

    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.xl,
        right: AppSpacing.xl,
        top: AppSpacing.sm,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.xl,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _isEditing ? 'Edit card' : 'New credit card',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.xl),
            CreditCardPreview(
              name: name.isEmpty ? 'Card name' : name,
              last4: CreditCardModel.isValidLast4(last4) ? last4 : null,
              color: Color(_color),
              limitLabel: limit == null || limit <= 0
                  ? null
                  : 'Limit ${CurrencyFormatter.formatCompact(limit, currencyCode: currency)}',
            ),
            const SizedBox(height: AppSpacing.xl),
            TextField(
              controller: _nameController,
              autofocus: !_isEditing,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              inputFormatters: [
                LengthLimitingTextInputFormatter(CreditCardModel.maxNameLength),
              ],
              decoration: InputDecoration(
                labelText: 'Card name',
                hintText: 'e.g. HDFC Millennia',
                errorText: _nameError,
              ),
              onChanged: (_) {
                if (_nameError != null) setState(() => _nameError = null);
              },
            ),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              controller: _last4Controller,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.next,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(4),
              ],
              decoration: InputDecoration(
                labelText: 'Last 4 digits (optional)',
                helperText: 'Only the last 4 — never your full card number.',
                errorText: _last4Error,
              ),
              onChanged: (_) {
                if (_last4Error != null) setState(() => _last4Error = null);
              },
            ),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              controller: _limitController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Credit limit (optional)',
                prefixText: '${CurrencyFormatter.symbolFor(currency)} ',
                errorText: _limitError,
              ),
              onChanged: (_) {
                if (_limitError != null) setState(() => _limitError = null);
              },
            ),
            const SizedBox(height: AppSpacing.xl),
            const SectionLabel('Colour'),
            Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.md,
              children: [
                for (final c in kCreditCardColors)
                  Semantics(
                    button: true,
                    selected: _color == c,
                    label: 'Card colour',
                    child: InkWell(
                      onTap: () => setState(() => _color = c),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(9),
                          border: Border.all(
                            color: _color == c
                                ? scheme.onSurface
                                : Colors.transparent,
                            width: 2,
                          ),
                        ),
                        child: CreditCardSwatch(color: Color(c), width: 46),
                      ),
                    ),
                  ),
              ],
            ),
            if (_saveError != null) ...[
              const SizedBox(height: AppSpacing.lg),
              Text(
                _saveError!,
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.error),
              ),
            ],
            const SizedBox(height: AppSpacing.xxl),
            // This Column aligns to start, so the button needs an explicit
            // full width rather than relying on the button theme.
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(_isEditing ? 'Save changes' : 'Add card'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
