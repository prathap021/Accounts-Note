import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/currency_formatter.dart';
import '../../models/budget_model.dart';
import '../../providers/budget_provider.dart';
import '../../providers/category_provider.dart';

class BudgetsScreen extends ConsumerWidget {
  const BudgetsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final budgetsAsync = ref.watch(budgetsStreamProvider);
    final progressAsync = ref.watch(budgetProgressProvider);
    final period = ref.watch(currentPeriodProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showBudgetForm(context, ref),
        child: const Icon(Icons.add_rounded),
      ),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            floating: true,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  period,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                Text(
                  'Budgets',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.4,
                      ),
                ),
              ],
            ),
            toolbarHeight: 72,
          ),
          budgetsAsync.when(
            data: (budgets) {
              if (budgets.isEmpty) {
                return const SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyState(
                    icon: Icons.pie_chart_outline_rounded,
                    title: 'No budgets this month',
                    message: 'Set a limit to stay on track with your spending.',
                  ),
                );
              }
              final spend = progressAsync.asData?.value ?? {};
              return SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                sliver: SliverList.separated(
                  itemCount: budgets.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 12),
                  itemBuilder: (context, i) {
                    final b = budgets[i];
                    final spent = b.categoryName != null
                        ? (spend[b.categoryName] ?? 0)
                        : spend.values.fold(0.0, (a, c) => a + c);
                    final percent =
                        b.limit <= 0 ? 0.0 : (spent / b.limit).clamp(0, 1.5);
                    final isOver = spent > b.limit;
                    final isWarning =
                        !isOver && percent * 100 >= b.alertThresholdPercent;
                    final barColor = isOver
                        ? AppColors.expense
                        : isWarning
                            ? AppColors.warning
                            : AppColors.income;

                    return Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainer,
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                          color: scheme.outlineVariant.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  b.categoryName ?? 'Overall budget',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w800),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline_rounded,
                                    size: 20),
                                onPressed: () => ref
                                    .read(budgetActionsProvider.notifier)
                                    .deleteBudget(b.id),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(999),
                            child: LinearProgressIndicator(
                              value: percent.toDouble().clamp(0, 1),
                              minHeight: 10,
                              backgroundColor: scheme.surfaceContainerHighest,
                              color: barColor,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            '${CurrencyFormatter.format(spent)} of ${CurrencyFormatter.format(b.limit)}',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          if (isOver)
                            const Padding(
                              padding: EdgeInsets.only(top: 6),
                              child: Text(
                                'Budget exceeded',
                                style: TextStyle(
                                  color: AppColors.expense,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            )
                          else if (isWarning)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                'Approaching limit (${b.alertThresholdPercent.toStringAsFixed(0)}%)',
                                style: const TextStyle(
                                  color: AppColors.warning,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              );
            },
            loading: () => const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => SliverFillRemaining(
              child: Center(child: Text('Error: $e')),
            ),
          ),
        ],
      ),
    );
  }

  void _showBudgetForm(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _BudgetFormSheet(),
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

  @override
  void dispose() {
    _limitController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync =
        ref.watch(categoriesStreamProvider(TransactionType.expense));
    final period = ref.watch(currentPeriodProvider);

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 8,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'New budget',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 16),
          categoriesAsync.when(
            data: (categories) => DropdownButtonFormField<String?>(
              initialValue: _categoryId,
              decoration: const InputDecoration(
                labelText: 'Category (blank = overall)',
              ),
              items: [
                const DropdownMenuItem(
                    value: null, child: Text('Overall monthly budget')),
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
          const SizedBox(height: 12),
          TextField(
            controller: _limitController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Monthly limit',
              prefixText: '₹ ',
            ),
          ),
          const SizedBox(height: 12),
          Text('Alert at ${_threshold.toStringAsFixed(0)}%'),
          Slider(
            value: _threshold,
            min: 50,
            max: 100,
            divisions: 10,
            label: '${_threshold.toStringAsFixed(0)}%',
            onChanged: (v) => setState(() => _threshold = v),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: () async {
              final limit = double.tryParse(_limitController.text);
              if (limit == null || limit <= 0) return;
              final budget = BudgetModel(
                id: '',
                period: period,
                categoryId: _categoryId,
                categoryName: _categoryName,
                limit: limit,
                alertThresholdPercent: _threshold,
                createdAt: DateTime.now(),
              );
              final navigator = Navigator.of(context);
              final ok =
                  await ref.read(budgetActionsProvider.notifier).setBudget(budget);
              if (ok && mounted) navigator.pop();
            },
            child: const Text('Save budget'),
          ),
        ],
      ),
    );
  }
}
