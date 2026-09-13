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
      floatingActionButton: const _AddFab(),
      body: RefreshIndicator(
        color: AppColors.brand,
        onRefresh: () async {
          ref.invalidate(dashboardSummaryProvider);
        },
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverAppBar(
              floating: true,
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Accounts Note',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  Text(
                    'Overview',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.4,
                        ),
                  ),
                ],
              ),
              toolbarHeight: 72,
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  summaryAsync.when(
                    data: (summary) => _SummarySection(summary: summary),
                    loading: () => const _SummarySkeleton(),
                    error: (e, _) => Text('Could not load summary: $e'),
                  ),
                  const SizedBox(height: 28),
                  SectionHeader(
                    title: 'Recent activity',
                    actionLabel: 'See all',
                    onAction: () => context.go('/transactions'),
                  ),
                  const SizedBox(height: 8),
                  recentAsync.when(
                    data: (txs) {
                      final recent = txs.take(5).toList();
                      if (recent.isEmpty) {
                        return const EmptyState(
                          icon: Icons.receipt_long_outlined,
                          title: 'No transactions yet',
                          message: 'Tap Add to log your first income or expense.',
                        );
                      }
                      return Container(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surfaceContainer,
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(
                            color: Theme.of(context)
                                .colorScheme
                                .outlineVariant
                                .withValues(alpha: 0.35),
                          ),
                        ),
                        child: Column(
                          children: [
                            for (var i = 0; i < recent.length; i++) ...[
                              TransactionTile(
                                transaction: recent[i],
                                onTap: () => context.push(
                                  '/transaction/edit',
                                  extra: recent[i],
                                ),
                              ),
                              if (i != recent.length - 1)
                                Divider(
                                  height: 1,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .outlineVariant
                                      .withValues(alpha: 0.35),
                                ),
                            ],
                          ],
                        ),
                      );
                    },
                    loading: () => const Padding(
                      padding: EdgeInsets.symmetric(vertical: 32),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                    error: (e, _) => Text('Could not load transactions: $e'),
                  ),
                ]),
              ),
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
        BalanceHeroCard(
          label: 'CURRENT BALANCE',
          amount: CurrencyFormatter.format(summary.balance),
          subtitle: 'Synced across your devices',
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: SummaryCard(
                label: 'Income',
                value: CurrencyFormatter.format(summary.totalIncome),
                icon: Icons.south_west_rounded,
                color: AppColors.income,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SummaryCard(
                label: 'Expenses',
                value: CurrencyFormatter.format(summary.totalExpense),
                icon: Icons.north_east_rounded,
                color: AppColors.expense,
              ),
            ),
          ],
        ),
        if (summary.expenseByCategory.isNotEmpty) ...[
          const SizedBox(height: 28),
          const SectionHeader(title: 'Expense breakdown'),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainer,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: Theme.of(context)
                    .colorScheme
                    .outlineVariant
                    .withValues(alpha: 0.35),
              ),
            ),
            child: SizedBox(
              height: 200,
              child: _ExpensePieChart(data: summary.expenseByCategory),
            ),
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
    Color(0xFF0F766E),
    Color(0xFF0284C7),
    Color(0xFFE11D48),
    Color(0xFFD97706),
    Color(0xFF7C3AED),
    Color(0xFF059669),
    Color(0xFFDB2777),
    Color(0xFF475569),
  ];

  @override
  Widget build(BuildContext context) {
    final entries = data.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = entries.fold<double>(0, (sum, e) => sum + e.value);

    return Row(
      children: [
        Expanded(
          flex: 5,
          child: PieChart(
            PieChartData(
              sectionsSpace: 3,
              centerSpaceRadius: 44,
              sections: [
                for (var i = 0; i < entries.length; i++)
                  PieChartSectionData(
                    value: entries[i].value,
                    color: _palette[i % _palette.length],
                    title:
                        '${(entries[i].value / total * 100).toStringAsFixed(0)}%',
                    radius: 46,
                    titleStyle: const TextStyle(
                      fontSize: 11,
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 4,
          child: ListView(
            children: [
              for (var i = 0; i < entries.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: _palette[i % _palette.length],
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          entries[i].key,
                          style: Theme.of(context).textTheme.bodySmall,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
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
    return const SizedBox(
      height: 220,
      child: Center(child: CircularProgressIndicator()),
    );
  }
}

class _AddFab extends StatelessWidget {
  const _AddFab();

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.extended(
      onPressed: () => showModalBottomSheet(
        context: context,
        builder: (ctx) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.income.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.south_west_rounded,
                        color: AppColors.income),
                  ),
                  title: const Text('Add income'),
                  subtitle: const Text('Salary, freelance, refunds…'),
                  onTap: () {
                    Navigator.pop(ctx);
                    context.push('/transaction/add', extra: TransactionType.income);
                  },
                ),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.expense.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.north_east_rounded,
                        color: AppColors.expense),
                  ),
                  title: const Text('Add expense'),
                  subtitle: const Text('Food, travel, bills…'),
                  onTap: () {
                    Navigator.pop(ctx);
                    context.push(
                        '/transaction/add', extra: TransactionType.expense);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
      icon: const Icon(Icons.add_rounded),
      label: const Text('Add'),
    );
  }
}
