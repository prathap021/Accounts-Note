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

    return Scaffold(
      appBar: AppBar(title: Text('Budgets · $period')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showBudgetForm(context, ref),
        child: const Icon(Icons.add),
      ),
      body: budgetsAsync.when(
        data: (budgets) {
          if (budgets.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No budgets set for this month yet.\nTap + to create your first budget.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          final spend = progressAsync.asData?.value ?? {};
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: budgets.length,
            itemBuilder: (context, i) {
              final b = budgets[i];
              final spent = b.categoryName != null ? (spend[b.categoryName] ?? 0) : spend.values.fold(0.0, (a, c) => a + c);
              final percent = b.limit <= 0 ? 0.0 : (spent / b.limit).clamp(0, 1.5);
              final isOver = spent > b.limit;
              final isWarning = !isOver && percent * 100 >= b.alertThresholdPercent;

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(b.categoryName ?? 'Overall Budget',
                              style: Theme.of(context).textTheme.titleMedium),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, size: 20),
                            onPressed: () =>
                                ref.read(budgetActionsProvider.notifier).deleteBudget(b.id),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: percent.toDouble().clamp(0, 1),
                          minHeight: 8,
                          backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                          color: isOver
                              ? AppColors.expense
                              : isWarning
                                  ? Colors.orange
                                  : AppColors.income,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${CurrencyFormatter.format(spent)} of ${CurrencyFormatter.format(b.limit)} spent',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      if (isOver)
                        const Padding(
                          padding: EdgeInsets.only(top: 4),
                          child: Text('Budget exceeded!',
                              style: TextStyle(color: AppColors.expense, fontWeight: FontWeight.w600)),
                        )
                      else if (isWarning)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text('Approaching limit (${b.alertThresholdPercent.toStringAsFixed(0)}%)',
                              style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.w600)),
                        ),
                    ],
                  ),
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
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
    final categoriesAsync = ref.watch(categoriesStreamProvider(TransactionType.expense));
    final period = ref.watch(currentPeriodProvider);

    return Padding(
      padding: EdgeInsets.only(
        left: 20, right: 20, top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('New Budget', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          categoriesAsync.when(
            data: (categories) => DropdownButtonFormField<String?>(
              initialValue: _categoryId,
              decoration: const InputDecoration(labelText: 'Category (leave blank for overall)'),
              items: [
                const DropdownMenuItem(value: null, child: Text('Overall monthly budget')),
                for (final c in categories) DropdownMenuItem(value: c.id, child: Text(c.name)),
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
            decoration: const InputDecoration(labelText: 'Monthly limit', prefixText: '₹ '),
          ),
          const SizedBox(height: 12),
          Text('Alert at ${_threshold.toStringAsFixed(0)}% of budget'),
          Slider(
            value: _threshold,
            min: 50,
            max: 100,
            divisions: 10,
            label: '${_threshold.toStringAsFixed(0)}%',
            onChanged: (v) => setState(() => _threshold = v),
          ),
          const SizedBox(height: 12),
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
              final ok = await ref.read(budgetActionsProvider.notifier).setBudget(budget);
              if (ok && mounted) navigator.pop();
            },
            child: const Text('Save Budget'),
          ),
        ],
      ),
    );
  }
}
