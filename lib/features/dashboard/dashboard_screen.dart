import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/currency_formatter.dart';
import '../../providers/dashboard_provider.dart';
import '../../providers/transaction_provider.dart';
import '../../widgets/summary_card.dart';
import '../../widgets/transaction_tile.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(dashboardSummaryProvider);
    final recentAsync = ref.watch(transactionsStreamProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Dashboard')),
      floatingActionButton: _AddFab(),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(dashboardSummaryProvider);
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            summaryAsync.when(
              data: (summary) => _SummarySection(summary: summary),
              loading: () => const _SummarySkeleton(),
              error: (e, _) => Text('Could not load summary: $e'),
            ),
            const SizedBox(height: 24),
            Text('Recent Transactions', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            recentAsync.when(
              data: (txs) {
                final recent = txs.take(5).toList();
                if (recent.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: Text('No transactions yet. Add your first one!')),
                  );
                }
                return Card(
                  child: Column(
                    children: [
                      for (final tx in recent)
                        TransactionTile(
                          transaction: tx,
                          onTap: () => context.push('/transaction/edit', extra: tx),
                        ),
                    ],
                  ),
                );
              },
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Text('Could not load transactions: $e'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummarySection extends StatelessWidget {
  final DashboardSummary summary;
  const _SummarySection({required this.summary});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          color: Theme.of(context).colorScheme.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Current Balance',
                    style: TextStyle(color: Theme.of(context).colorScheme.onPrimaryContainer)),
                const SizedBox(height: 8),
                Text(
                  CurrencyFormatter.format(summary.balance),
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onPrimaryContainer),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: SummaryCard(
                label: 'Income',
                value: CurrencyFormatter.format(summary.totalIncome),
                icon: Icons.arrow_downward,
                color: AppColors.income,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SummaryCard(
                label: 'Expenses',
                value: CurrencyFormatter.format(summary.totalExpense),
                icon: Icons.arrow_upward,
                color: AppColors.expense,
              ),
            ),
          ],
        ),
        if (summary.expenseByCategory.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text('Expense Breakdown', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          SizedBox(
            height: 200,
            child: _ExpensePieChart(data: summary.expenseByCategory),
          ),
        ],
      ],
    );
  }
}

class _ExpensePieChart extends StatelessWidget {
  final Map<String, double> data;
  const _ExpensePieChart({required this.data});

  static const _palette = [
    Color(0xFFEF6C00), Color(0xFF1E88E5), Color(0xFFD81B60), Color(0xFF6D4C41),
    Color(0xFF8E24AA), Color(0xFFE53935), Color(0xFF3949AB), Color(0xFF00897B),
  ];

  @override
  Widget build(BuildContext context) {
    final entries = data.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final total = entries.fold<double>(0, (sum, e) => sum + e.value);

    return Row(
      children: [
        Expanded(
          child: PieChart(
            PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: 40,
              sections: [
                for (var i = 0; i < entries.length; i++)
                  PieChartSectionData(
                    value: entries[i].value,
                    color: _palette[i % _palette.length],
                    title: '${(entries[i].value / total * 100).toStringAsFixed(0)}%',
                    radius: 50,
                    titleStyle: const TextStyle(fontSize: 11, color: Colors.white),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ListView(
            children: [
              for (var i = 0; i < entries.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Container(width: 10, height: 10, color: _palette[i % _palette.length]),
                      const SizedBox(width: 6),
                      Expanded(
                          child: Text(entries[i].key,
                              style: const TextStyle(fontSize: 12),
                              overflow: TextOverflow.ellipsis)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SummarySkeleton extends StatelessWidget {
  const _SummarySkeleton();
  @override
  Widget build(BuildContext context) {
    return const SizedBox(height: 220, child: Center(child: CircularProgressIndicator()));
  }
}

class _AddFab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.extended(
      onPressed: () => showModalBottomSheet(
        context: context,
        builder: (ctx) => SafeArea(
          child: Wrap(children: [
            ListTile(
              leading: const Icon(Icons.arrow_downward, color: AppColors.income),
              title: const Text('Add Income'),
              onTap: () {
                Navigator.pop(ctx);
                context.push('/transaction/add', extra: TransactionType.income);
              },
            ),
            ListTile(
              leading: const Icon(Icons.arrow_upward, color: AppColors.expense),
              title: const Text('Add Expense'),
              onTap: () {
                Navigator.pop(ctx);
                context.push('/transaction/add', extra: TransactionType.expense);
              },
            ),
          ]),
        ),
      ),
      icon: const Icon(Icons.add),
      label: const Text('Add'),
    );
  }
}
