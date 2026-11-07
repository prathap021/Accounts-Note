import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:number_to_words/number_to_words.dart';

import '../../core/constants/app_constants.dart';
import '../../core/constants/category_icons.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/utils/result.dart';
import '../../core/utils/snackbar_helper.dart';
import '../../models/category_model.dart';
import '../../models/credit_card_model.dart';
import '../../models/transaction_model.dart';
import '../../providers/category_provider.dart';
import '../../providers/credit_card_provider.dart';
import '../../providers/dashboard_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/subscription_provider.dart';
import '../../providers/transaction_provider.dart';
import '../../widgets/credit_card_visual.dart';
import '../credit_cards/credit_cards_screen.dart';
import '../subscription/limit_reached_sheet.dart';

const _paymentMethods = ['Cash', 'Card', 'UPI', 'Bank Transfer', 'Wallet', 'Other'];

const _paymentIcons = <String, IconData>{
  'Cash': Icons.payments_outlined,
  'Card': Icons.credit_card_rounded,
  'UPI': Icons.qr_code_rounded,
  'Bank Transfer': Icons.account_balance_rounded,
  'Wallet': Icons.account_balance_wallet_outlined,
  'Other': Icons.more_horiz_rounded,
  kCreditCardPaymentMethod: Icons.credit_card_rounded,
};

/// What the payment sheet hands back.
sealed class _PaymentChoice {
  const _PaymentChoice();
}

class _MethodChoice extends _PaymentChoice {
  final String method;
  const _MethodChoice(this.method);
}

class _CardChoice extends _PaymentChoice {
  final CreditCardModel card;
  const _CardChoice(this.card);
}

class _AddCardChoice extends _PaymentChoice {
  const _AddCardChoice();
}

class AddEditTransactionScreen extends ConsumerStatefulWidget {
  final TransactionType initialType;
  final TransactionModel? existing;

  const AddEditTransactionScreen({
    super.key,
    this.initialType = TransactionType.expense,
    this.existing,
  });

  @override
  ConsumerState<AddEditTransactionScreen> createState() =>
      _AddEditTransactionScreenState();
}

class _AddEditTransactionScreenState
    extends ConsumerState<AddEditTransactionScreen> {
  final _formKey = GlobalKey<FormState>();
  late TransactionType _type;
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  CategoryModel? _selectedCategory;
  DateTime _date = DateTime.now();
  String _paymentMethod = _paymentMethods.first;

  /// Set when the payment method is one of the user's credit cards.
  String? _creditCardId;

  /// The card's name as last stored, shown if the card has since been deleted.
  String? _creditCardName;
  bool _saving = false;
  bool _categoryMissing = false;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _type = existing?.type ?? widget.initialType;
    if (existing != null) {
      _amountController.text = existing.amount.toStringAsFixed(2);
      _noteController.text = existing.note ?? '';
      _date = existing.date;
      _paymentMethod = existing.paymentMethod ?? _paymentMethods.first;
      _creditCardId = existing.creditCardId;
      _creditCardName = existing.creditCardName;
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Color get _accent =>
      _type == TransactionType.income ? AppColors.income : AppColors.expense;

  String _title() {
    if (_isEditing) return 'Edit transaction';
    return _type == TransactionType.income ? 'Add income' : 'Add expense';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final currency = ref.watch(settingsProvider).currency;
    final categoriesAsync = ref.watch(categoriesStreamProvider(_type));
    final card = ref.watch(creditCardLookupProvider)[_creditCardId];

    // Pre-select the existing category once the stream resolves.
    categoriesAsync.whenData((categories) {
      if (_selectedCategory == null) {
        if (widget.existing != null) {
          _selectedCategory = categories
              .where((c) => c.id == widget.existing!.categoryId)
              .firstOrNull;
        }
        _selectedCategory ??= categories.firstOrNull;
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(_title()),
        actions: [
          if (_isEditing)
            IconButton(
              tooltip: 'Delete transaction',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: _confirmDelete,
            ),
          const SizedBox(width: AppSpacing.sm),
        ],
      ),
      // Keep Save in thumb reach, above the keyboard, on every screen size.
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.gutter,
            AppSpacing.sm,
            AppSpacing.gutter,
            AppSpacing.md,
          ),
          child: FilledButton(
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(
              backgroundColor: _accent,
              foregroundColor: Colors.white,
            ),
            child: _saving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(_isEditing ? 'Save changes' : 'Add transaction'),
          ),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.gutter,
            AppSpacing.sm,
            AppSpacing.gutter,
            AppSpacing.xl,
          ),
          children: [
            SegmentedButton<TransactionType>(
              segments: const [
                ButtonSegment(
                  value: TransactionType.expense,
                  label: Text('Expense'),
                  icon: Icon(Icons.north_east_rounded, size: 18),
                ),
                ButtonSegment(
                  value: TransactionType.income,
                  label: Text('Income'),
                  icon: Icon(Icons.south_west_rounded, size: 18),
                ),
              ],
              selected: {_type},
              showSelectedIcon: false,
              onSelectionChanged: (s) {
                setState(() {
                  _type = s.first;
                  _selectedCategory = null;
                });
              },
            ),
            const SizedBox(height: AppSpacing.xl),
            _AmountField(
              controller: _amountController,
              accent: _accent,
              currency: currency,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: AppSpacing.xl),
            Row(
              children: [
                const Expanded(child: SectionLabel('Category')),
                TextButton(
                  onPressed: () => context.push('/categories'),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                  ),
                  child: const Text('Manage'),
                ),
              ],
            ),
            categoriesAsync.when(
              data: (categories) {
                if (categories.isEmpty) {
                  return AppCard(
                    onTap: () => context.push('/categories'),
                    child: Row(
                      children: [
                        Icon(Icons.add_circle_outline_rounded,
                            color: scheme.primary),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Text(
                            'No categories yet — tap to create one.',
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: [
                        for (final c in categories)
                          _CategoryChip(
                            category: c,
                            selected: _selectedCategory?.id == c.id,
                            onTap: () => setState(() {
                              _selectedCategory = c;
                              _categoryMissing = false;
                            }),
                          ),
                      ],
                    ),
                    if (_categoryMissing)
                      Padding(
                        padding: const EdgeInsets.only(
                          top: AppSpacing.sm,
                          left: AppSpacing.xs,
                        ),
                        child: Text(
                          'Select a category',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: scheme.error),
                        ),
                      ),
                  ],
                );
              },
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => const AppErrorState(
                message: "We couldn't load your categories.",
                compact: true,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            const SectionLabel('Details'),
            AppCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  _DetailRow(
                    icon: Icons.event_rounded,
                    label: 'Date & time',
                    value: DateFormat('EEE, MMM d · h:mm a').format(_date),
                    onTap: _pickDateTime,
                  ),
                  Divider(height: 1, color: scheme.outlineVariant),
                  _DetailRow(
                    icon: _paymentIcons[_paymentMethod] ??
                        Icons.account_balance_wallet_outlined,
                    label: 'Payment method',
                    value: card?.displayName ??
                        _creditCardName ??
                        _paymentMethod,
                    onTap: _pickPaymentMethod,
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            const SectionLabel('Note'),
            TextFormField(
              controller: _noteController,
              decoration: const InputDecoration(
                hintText: 'What was this for? (optional)',
              ),
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2015),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_date),
    );
    if (time == null) return;
    setState(() {
      _date = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  Future<void> _pickPaymentMethod() async {
    final picked = await showModalBottomSheet<_PaymentChoice>(
      context: context,
      // Grows with the number of cards; scrolls rather than overflowing, and
      // stops below the status bar.
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _PaymentMethodSheet(
        method: _paymentMethod,
        creditCardId: _creditCardId,
      ),
    );
    if (picked == null || !mounted) return;

    switch (picked) {
      case _MethodChoice(:final method):
        setState(() {
          _paymentMethod = method;
          _creditCardId = null;
          _creditCardName = null;
        });
      case _CardChoice(:final card):
        _selectCard(card);
      case _AddCardChoice():
        // A card added from here is the one being paid with.
        final card = await showCreditCardForm(context);
        if (card != null && mounted) _selectCard(card);
    }
  }

  void _selectCard(CreditCardModel card) {
    setState(() {
      _paymentMethod = kCreditCardPaymentMethod;
      _creditCardId = card.id;
      _creditCardName = card.displayName;
    });
  }

  Future<void> _save() async {
    final formOk = _formKey.currentState!.validate();
    final hasCategory = _selectedCategory != null;
    if (!hasCategory) setState(() => _categoryMissing = true);
    if (!formOk || !hasCategory) return;

    setState(() => _saving = true);

    final amount = double.parse(_amountController.text);
    final now = DateTime.now();
    final card = ref.read(creditCardLookupProvider)[_creditCardId];
    final tx = TransactionModel(
      id: widget.existing?.id ?? '',
      type: _type,
      amount: amount,
      categoryId: _selectedCategory!.id,
      categoryName: _selectedCategory!.name,
      note: _noteController.text.trim().isEmpty
          ? null
          : _noteController.text.trim(),
      date: _date,
      paymentMethod: _paymentMethod,
      creditCardId: _creditCardId,
      // The card's current name if it still exists, so a rename since it was
      // picked is what gets stored.
      creditCardName: _creditCardId == null
          ? null
          : card?.displayName ?? _creditCardName,
      createdAt: widget.existing?.createdAt ?? now,
      updatedAt: now,
    );

    final notifier = ref.read(transactionActionsProvider.notifier);
    final success = _isEditing
        ? await notifier.updateTransaction(tx)
        : await notifier.addTransaction(tx) != false;

    if (!mounted) return;
    setState(() => _saving = false);

    if (success) {
      ref.invalidate(dashboardSummaryProvider);
      SnackbarHelper.showSuccess(
        context,
        _isEditing ? 'Transaction updated' : 'Transaction added',
      );
      Navigator.of(context).pop();
    } else {
      final err = ref.read(transactionActionsProvider);
      if (err is AsyncError && err.error is DailyLimitReached) {
        await showDailyLimitReachedSheet(
          context,
          err.error as DailyLimitReached,
        );
        return;
      }
      final failure = err is AsyncError && err.error is AppFailure
          ? err.error as AppFailure
          : null;
      final msg = failure?.userMessage ?? 'Something went wrong. Please try again.';
      SnackbarHelper.showError(context, msg);
    }
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete transaction?'),
        content: const Text('This action cannot be undone.'),
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
    if (confirmed == true && widget.existing != null && mounted) {
      await ref
          .read(transactionActionsProvider.notifier)
          .deleteTransaction(widget.existing!.id);
      ref.invalidate(dashboardSummaryProvider);
      if (mounted) Navigator.of(context).pop();
    }
  }
}

/// The amount is the point of the screen, so it gets its own tinted panel
/// with the currency symbol and a plain-language echo of what was typed.
class _AmountField extends StatelessWidget {
  final TextEditingController controller;
  final Color accent;
  final String currency;
  final ValueChanged<String> onChanged;

  const _AmountField({
    required this.controller,
    required this.accent,
    required this.currency,
    required this.onChanged,
  });

  String? _inWords() {
    if (!CurrencyFormatter.supportsWords(currency)) return null;
    final amount = int.tryParse(controller.text.trim().split('.').first);
    if (amount == null || amount <= 0) return null;
    try {
      final words = NumberToWord().convert('en-in', amount).trim();
      if (words.isEmpty) return null;
      return '${words[0].toUpperCase()}${words.substring(1)} rupees';
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final words = _inWords();

    return AppCard(
      color: accent.withValues(alpha: 0.06),
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'AMOUNT',
            style: theme.textTheme.labelSmall?.copyWith(
              color: accent,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextFormField(
            controller: controller,
            autofocus: controller.text.isEmpty,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: theme.textTheme.displaySmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: accent,
              letterSpacing: -1,
            ),
            decoration: InputDecoration(
              filled: false,
              isDense: true,
              contentPadding: EdgeInsets.zero,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              errorBorder: InputBorder.none,
              focusedErrorBorder: InputBorder.none,
              hintText: '0',
              hintStyle: theme.textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: accent.withValues(alpha: 0.35),
              ),
              prefixText: '${CurrencyFormatter.symbolFor(currency)} ',
              prefixStyle: theme.textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: accent.withValues(alpha: 0.7),
              ),
            ),
            onChanged: onChanged,
            validator: (v) {
              final val = double.tryParse(v ?? '');
              if (val == null || val <= 0) return 'Enter a valid amount';
              return null;
            },
          ),
          if (words != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              words,
              style: theme.textTheme.bodySmall?.copyWith(
                color: accent.withValues(alpha: 0.9),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final CategoryModel category;
  final bool selected;
  final VoidCallback onTap;

  const _CategoryChip({
    required this.category,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = Color(category.color);

    return ChoiceChip(
      selected: selected,
      onSelected: (_) => onTap(),
      avatar: Icon(iconFor(category.icon), size: 18, color: color),
      label: Text(category.name),
      selectedColor: color.withValues(alpha: 0.16),
      side: BorderSide(
        color: selected
            ? color.withValues(alpha: 0.6)
            : Theme.of(context).colorScheme.outlineVariant,
      ),
      labelStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
            fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
          ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return ListTile(
      onTap: onTap,
      shape: const RoundedRectangleBorder(),
      leading: Container(
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          color: scheme.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, size: 19, color: scheme.primary),
      ),
      title: Text(
        label,
        style: theme.textTheme.bodySmall?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
      subtitle: Text(
        value,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: scheme.onSurface,
        ),
      ),
      trailing: Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
    );
  }
}

/// The plain payment methods, then the user's own credit cards, so marking an
/// expense against a particular card is a single tap.
class _PaymentMethodSheet extends ConsumerWidget {
  final String method;
  final String? creditCardId;

  const _PaymentMethodSheet({required this.method, this.creditCardId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final cards = ref.watch(creditCardsStreamProvider).asData?.value ?? const [];
    final check = Icon(Icons.check_circle_rounded, color: scheme.primary);
    // Card swatches are wider than icons; a shared leading width keeps every
    // title on one line of alignment.
    const leadingWidth = 32.0;

    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                0,
                AppSpacing.xl,
                AppSpacing.md,
              ),
              child: Text('Payment method', style: theme.textTheme.titleLarge),
            ),
            for (final m in _paymentMethods)
              ListTile(
                minLeadingWidth: leadingWidth,
                leading: Icon(_paymentIcons[m] ?? Icons.more_horiz_rounded),
                title: Text(m),
                trailing: creditCardId == null && m == method ? check : null,
                onTap: () => Navigator.pop(context, _MethodChoice(m)),
              ),
            const Padding(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.lg,
                0,
              ),
              child: SectionLabel('Credit cards'),
            ),
            for (final c in cards)
              ListTile(
                minLeadingWidth: leadingWidth,
                leading:
                    CreditCardSwatch(color: Color(c.color), width: leadingWidth),
                title: Text(c.name),
                subtitle: c.last4 == null ? null : Text('•••• ${c.last4}'),
                trailing: c.id == creditCardId ? check : null,
                onTap: () => Navigator.pop(context, _CardChoice(c)),
              ),
            ListTile(
              minLeadingWidth: leadingWidth,
              leading: Icon(Icons.add_card_rounded, color: scheme.primary),
              title: Text(
                cards.isEmpty ? 'Add your first credit card' : 'Add a credit card',
                style: TextStyle(
                  color: scheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onTap: () => Navigator.pop(context, const _AddCardChoice()),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
        ),
      ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
