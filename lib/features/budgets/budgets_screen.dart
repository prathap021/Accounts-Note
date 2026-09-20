import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/responsive.dart';
import '../../core/utils/currency_formatter.dart';
import '../../models/budget_model.dart';
import '../../providers/budget_provider.dart';
import '../../providers/category_provider.dart';
import '../../providers/settings_provider.dart';

String _periodLabel(String period) {
  try {
    return DateFormat('MMMM yyyy').format(DateTime.parse('$period-01'));
  } catch (_) {
    return period;
  }
}

/// Spend state of a single budget, so the card and the overview agree on what
/// counts as "over" or "close to the limit".
class _BudgetStatus {
  final double spent;
  final double limit;
  final double thresholdPercent;

  const _BudgetStatus({
    required this.spent,
    required this.limit,
    required this.thresholdPercent,
  });

  double get ratio => limit <= 0 ? 0 : spent / limit;
  double get remaining => limit - spent;
  bool get isOver => spent > limit;
  bool get isWarning => !isOver && ratio * 100 >= thresholdPercent;

  Color get color => isOver
      ? AppColors.expense
      : isWarning
          ? AppColors.warning
          : AppColors.income;

  String get label => isOver
      ? 'Over budget'
      : isWarning
          ? 'Close to limit'
          : 'On track';
}

class BudgetsScreen extends ConsumerWidget {
  const BudgetsScreen({super.key});

  double _spentFor(BudgetModel b, Map<String, double> spend) {
    return b.categoryName != null
        ? (spend[b.categoryName] ?? 0)
        : spend.values.fold(0.0, (a, c) => a + c);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final budgetsAsync = ref.watch(budgetsStreamProvider);
    final progressAsync = ref.watch(budgetProgressProvider);
    final period = ref.watch(currentPeriodProvider);
    final currency = ref.watch(settingsProvider).currency;

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab-budgets',
        onPressed: () => _showBudgetForm(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New budget'),
      ),
      body: RefreshIndicator(
        color: AppColors.brand,
        onRefresh: () async => ref.invalidate(budgetProgressProvider),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            AppSliverHeader(
              eyebrow: _periodLabel(period),
              title: 'Budgets',
            ),
            budgetsAsync.when(
              data: (budgets) {
                if (budgets.isEmpty) {
                  return SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: EmptyState(
                        icon: Icons.pie_chart_outline_rounded,
                        title: 'No budgets this month',
                        message:
                            'Set a monthly limit for a category — or for everything — and track it here.',
                        actionLabel: 'Create a budget',
                        onAction: () => _showBudgetForm(context),
                      ),
                    ),
                  );
                }

                final spend = progressAsync.asData?.value ?? {};
                final totalLimit =
                    budgets.fold<double>(0, (sum, b) => sum + b.limit);
                final totalSpent = budgets.fold<double>(
                  0,
                  (sum, b) => sum + _spentFor(b, spend),
                );

                return SliverPadding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.gutter,
                    AppSpacing.xs,
                    AppSpacing.gutter,
                    AppSpacing.scrollBottom,
                  ),
                  sliver: SliverList.builder(
                    itemCount: budgets.length + 1,
                    itemBuilder: (context, i) {
                      if (i == 0) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.xl),
                          child: _BudgetOverview(
                            totalLimit: totalLimit,
                            totalSpent: totalSpent,
                            count: budgets.length,
                            currency: currency,
                          ),
                        );
                      }
                      final b = budgets[i - 1];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.md),
                        child: _BudgetCard(
                          budget: b,
                          status: _BudgetStatus(
                            spent: _spentFor(b, spend),
                            limit: b.limit,
                            thresholdPercent: b.alertThresholdPercent,
                          ),
                          currency: currency,
                        ),
                      );
                    },
                  ),
                );
              },
              loading: () => const SliverToBoxAdapter(
                child: Padding(
                  padding: AppSpacing.screenPadding,
                  child: Column(
                    children: [
                      SkeletonBox(height: 120, radius: AppRadii.card),
                      SizedBox(height: AppSpacing.xl),
                      SkeletonBox(height: 132, radius: AppRadii.card),
                      SizedBox(height: AppSpacing.md),
                      SkeletonBox(height: 132, radius: AppRadii.card),
                    ],
                  ),
                ),
              ),
              error: (e, _) => SliverFillRemaining(
                hasScrollBody: false,
                child: Padding(
                  padding: AppSpacing.screenPadding,
                  child: Center(
                    child: AppErrorState(
                      message: "We couldn't load your budgets.",
                      onRetry: () => ref.invalidate(budgetsStreamProvider),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showBudgetForm(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _BudgetFormSheet(),
    );
  }
}

class _BudgetOverview extends StatelessWidget {
  final double totalLimit;
  final double totalSpent;
  final int count;
  final String currency;

  const _BudgetOverview({
    required this.totalLimit,
    required this.totalSpent,
    required this.count,
    required this.currency,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final remaining = totalLimit - totalSpent;
    final ratio = totalLimit <= 0 ? 0.0 : (totalSpent / totalLimit).clamp(0.0, 1.0);
    final over = remaining < 0;

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  over ? 'Over your limits by' : 'Left to spend',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                '$count active',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            CurrencyFormatter.format(remaining.abs(), currencyCode: currency),
            style: theme.textTheme.headlineSmall?.copyWith(
              color: over ? AppColors.expense : scheme.onSurface,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadii.pill),
            child: LinearProgressIndicator(
              value: ratio.toDouble(),
              minHeight: 8.rh,
              backgroundColor: scheme.surfaceContainerHighest,
              color: over ? AppColors.expense : AppColors.brand,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            '${CurrencyFormatter.format(totalSpent, currencyCode: currency)} spent of '
            '${CurrencyFormatter.format(totalLimit, currencyCode: currency)}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _BudgetCard extends ConsumerWidget {
  final BudgetModel budget;
  final _BudgetStatus status;
  final String currency;

  const _BudgetCard({
    required this.budget,
    required this.status,
    required this.currency,
  });

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this budget?'),
        content: Text(
          'The limit for ${budget.categoryName ?? 'your overall budget'} will be '
          'removed. Your transactions are not affected.',
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
    if (confirmed == true) {
      await ref.read(budgetActionsProvider.notifier).deleteBudget(budget.id);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final percent = (status.ratio * 100).clamp(0, 999).toStringAsFixed(0);

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40.rr,
                height: 40.rr,
                decoration: BoxDecoration(
                  color: status.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  budget.categoryName == null
                      ? Icons.account_balance_wallet_rounded
                      : Icons.sell_rounded,
                  size: 19,
                  color: status.color,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      budget.categoryName ?? 'Overall budget',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      status.label,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: status.color,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '$percent%',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: status.color,
                  fontWeight: FontWeight.w800,
                ),
              ),
              IconButton(
                tooltip: 'Delete budget',
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  Icons.delete_outline_rounded,
                  size: 20,
                  color: scheme.onSurfaceVariant,
                ),
                onPressed: () => _confirmDelete(context, ref),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadii.pill),
            child: LinearProgressIndicator(
              value: status.ratio.clamp(0.0, 1.0).toDouble(),
              minHeight: 9.rh,
              backgroundColor: scheme.surfaceContainerHighest,
              color: status.color,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${CurrencyFormatter.format(status.spent, currencyCode: currency)}'
                  ' of ${CurrencyFormatter.format(status.limit, currencyCode: currency)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              Text(
                status.isOver
                    ? '${CurrencyFormatter.format(status.remaining.abs(), currencyCode: currency)} over'
                    : '${CurrencyFormatter.format(status.remaining, currencyCode: currency)} left',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: status.color,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BudgetFormSheet extends ConsumerStatefulWidget {
  const _BudgetFormSheet();
  @override
  ConsumerState<_BudgetFormSheet> createState() => _BudgetFormSheetState();
}

class _BudgetFormSheetState extends ConsumerState<_BudgetFormSheet> {
  final _limitController = TextEditingController();
  String? _categoryId;
  String? _categoryName;
  double _threshold = 80;
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _limitController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final limit = double.tryParse(_limitController.text.trim());
    if (limit == null || limit <= 0) {
      setState(() => _error = 'Enter a limit greater than zero');
      return;
    }
    setState(() {
      _error = null;
      _saving = true;
    });

    final budget = BudgetModel(
      id: '',
      period: ref.read(currentPeriodProvider),
      categoryId: _categoryId,
      categoryName: _categoryName,
      limit: limit,
      alertThresholdPercent: _threshold,
      createdAt: DateTime.now(),
    );

    final navigator = Navigator.of(context);
    final ok = await ref.read(budgetActionsProvider.notifier).setBudget(budget);
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) {
      navigator.pop();
    } else {
      setState(() => _error = "That budget couldn't be saved. Please try again.");
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final categoriesAsync =
        ref.watch(categoriesStreamProvider(TransactionType.expense));
    final period = ref.watch(currentPeriodProvider);
    final currency = ref.watch(settingsProvider).currency;

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
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('New budget', style: theme.textTheme.titleLarge),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Applies to ${_periodLabel(period)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            const SectionLabel('Category'),
            categoriesAsync.when(
              data: (categories) => DropdownButtonFormField<String?>(
                initialValue: _categoryId,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.sell_outlined),
                ),
                items: [
                  const DropdownMenuItem(
                    value: null,
                    child: Text('Overall monthly budget'),
                  ),
                  for (final c in categories)
                    DropdownMenuItem(value: c.id, child: Text(c.name)),
                ],
                onChanged: (id) {
                  setState(() {
                    _categoryId = id;
                    _categoryName = id == null
                        ? null
                        : categories.firstWhere((c) => c.id == id).name;
                  });
                },
              ),
              loading: () => const LinearProgressIndicator(),
              error: (e, st) => const SizedBox.shrink(),
            ),
            const SizedBox(height: AppSpacing.xl),
            const SectionLabel('Monthly limit'),
            TextField(
              controller: _limitController,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: theme.textTheme.headlineSmall,
              decoration: InputDecoration(
                hintText: '0',
                errorText: _error,
                prefixText: '${CurrencyFormatter.symbolFor(currency)} ',
                prefixStyle: theme.textTheme.headlineSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
            ),
            const SizedBox(height: AppSpacing.xl),
            SectionLabel('Alert me at ${_threshold.toStringAsFixed(0)}%'),
            Slider(
              value: _threshold,
              min: 50,
              max: 100,
              divisions: 10,
              label: '${_threshold.toStringAsFixed(0)}%',
              onChanged: (v) => setState(() => _threshold = v),
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: scheme.onPrimary,
                      ),
                    )
                  : const Text('Save budget'),
            ),
          ],
        ),
      ),
    );
  }
}
