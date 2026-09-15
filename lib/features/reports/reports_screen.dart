import 'dart:io';

import 'package:csv/csv.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/utils/snackbar_helper.dart';
import '../../providers/auth_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/transaction_provider.dart';

enum ReportRange { week, month, year }

extension ReportRangeLabel on ReportRange {
  String get label => switch (this) {
        ReportRange.week => 'Week',
        ReportRange.month => 'Month',
        ReportRange.year => 'Year',
      };

  String get caption => switch (this) {
        ReportRange.week => 'This week so far',
        ReportRange.month => 'This month so far',
        ReportRange.year => 'This year so far',
      };
}

class _ReportRangeNotifier extends Notifier<ReportRange> {
  @override
  ReportRange build() => ReportRange.month;
  void set(ReportRange r) => state = r;
}

final reportRangeProvider =
    NotifierProvider<_ReportRangeNotifier, ReportRange>(_ReportRangeNotifier.new);

class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});

  DateTimeRange _rangeFor(ReportRange r) {
    final now = DateTime.now();
    switch (r) {
      case ReportRange.week:
        final start = now.subtract(Duration(days: now.weekday - 1));
        return DateTimeRange(
            start: DateTime(start.year, start.month, start.day), end: now);
      case ReportRange.month:
        return DateTimeRange(start: DateTime(now.year, now.month, 1), end: now);
      case ReportRange.year:
        return DateTimeRange(start: DateTime(now.year, 1, 1), end: now);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final range = ref.watch(reportRangeProvider);
    final uid = ref.watch(currentUidProvider);
    final currency = ref.watch(settingsProvider).currency;
    final dateRange = _rangeFor(range);
    final dateFormat = DateFormat('MMM d');

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          AppSliverHeader(
            eyebrow: range.caption,
            title: 'Reports',
            actions: [
              HeaderAction(
                icon: Icons.ios_share_rounded,
                tooltip: 'Export as CSV',
                onTap: uid == null
                    ? null
                    : () => _exportCsv(context, ref, uid, dateRange),
              ),
            ],
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.gutter,
              AppSpacing.xs,
              AppSpacing.gutter,
              AppSpacing.scrollBottom,
            ),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                SegmentedButton<ReportRange>(
                  segments: [
                    for (final r in ReportRange.values)
                      ButtonSegment(value: r, label: Text(r.label)),
                  ],
                  selected: {range},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) =>
                      ref.read(reportRangeProvider.notifier).set(s.first),
                ),
                const SizedBox(height: AppSpacing.sm),
                Padding(
                  padding: const EdgeInsets.only(left: AppSpacing.xs),
                  child: Text(
                    '${dateFormat.format(dateRange.start)} – ${dateFormat.format(dateRange.end)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                if (uid == null)
                  const SizedBox.shrink()
                else
                  FutureBuilder(
                    future: ref.read(transactionRepositoryProvider).sumByType(
                          uid,
                          start: dateRange.start,
                          end: dateRange.end,
                        ),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const _ReportsSkeleton();
                      }
                      final sums = snapshot.data!.when(
                        success: (d) => d,
                        failure: (_) => <TransactionType, double>{},
                      );
                      // Firestore/num maps can surface ints; normalize for chart widgets.
                      final income =
                          (sums[TransactionType.income] ?? 0).toDouble();
                      final expense =
                          (sums[TransactionType.expense] ?? 0).toDouble();

                      if (income == 0 && expense == 0) {
                        return const AppCard(
                          padding: EdgeInsets.zero,
                          child: EmptyState(
                            icon: Icons.insights_outlined,
                            title: 'Nothing to report yet',
                            message:
                                'Once you log transactions in this period, your totals and chart appear here.',
                          ),
                        );
                      }

                      return _ReportBody(
                        income: income,
                        expense: expense,
                        currency: currency,
                      );
                    },
                  ),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _exportCsv(
    BuildContext context,
    WidgetRef ref,
    String uid,
    DateTimeRange range,
  ) async {
    final result = await ref
        .read(transactionRepositoryProvider)
        .fetchPage(uid: uid, pageSize: 1000);
    if (!context.mounted) return;
    result.when(
      success: (all) async {
        final txs = all
            .where((t) =>
                !t.date.isBefore(range.start) && !t.date.isAfter(range.end))
            .toList();
        final rows = <List<dynamic>>[
          ['Date', 'Type', 'Category', 'Amount', 'Payment Method', 'Note'],
          for (final t in txs)
            [
              DateFormat('yyyy-MM-dd HH:mm').format(t.date),
              t.type.name,
              t.categoryName,
              t.amount,
              t.paymentMethod ?? '',
              t.note ?? '',
            ],
        ];
        final csv = Csv().encode(rows);
        final dir = await getTemporaryDirectory();
        final file = File('${dir.path}/transactions_export.csv');
        await file.writeAsString(csv);
        await SharePlus.instance.share(
          ShareParams(files: [XFile(file.path)], text: 'Transaction export'),
        );
      },
      failure: (f) => SnackbarHelper.showError(context, f.userMessage),
    );
  }
}

class _ReportBody extends StatelessWidget {
  final double income;
  final double expense;
  final String currency;

  const _ReportBody({
    required this.income,
    required this.expense,
    required this.currency,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final net = income - expense;
    final savingsRate = income > 0 ? (net / income * 100) : null;
    final maxY = [income, expense].reduce((a, b) => a > b ? a : b);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _StatTile(
                label: 'Income',
                value: CurrencyFormatter.format(income, currencyCode: currency),
                icon: Icons.south_west_rounded,
                color: AppColors.income,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: _StatTile(
                label: 'Expenses',
                value: CurrencyFormatter.format(expense, currencyCode: currency),
                icon: Icons.north_east_rounded,
                color: AppColors.expense,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        AppCard(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      net >= 0 ? 'Net saved' : 'Net overspend',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        CurrencyFormatter.format(
                          net.abs(),
                          currencyCode: currency,
                        ),
                        style: theme.textTheme.headlineSmall?.copyWith(
                          color:
                              net >= 0 ? AppColors.income : AppColors.expense,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (savingsRate != null) ...[
                const SizedBox(width: AppSpacing.lg),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                    vertical: AppSpacing.md,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(AppRadii.control),
                  ),
                  child: Column(
                    children: [
                      Text(
                        '${savingsRate.toStringAsFixed(0)}%',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        'of income',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xxl),
        const SectionHeader(title: 'Income vs expenses'),
        const SizedBox(height: AppSpacing.md),
        AppCard(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.sm,
            AppSpacing.xl,
            AppSpacing.lg,
            AppSpacing.md,
          ),
          child: SizedBox(
            height: 230,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: maxY <= 0 ? 1 : maxY * 1.2,
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (_) => scheme.inverseSurface,
                    getTooltipItem: (group, _, rod, _) => BarTooltipItem(
                      '${group.x == 0 ? 'Income' : 'Expenses'}\n'
                      '${CurrencyFormatter.format(rod.toY, currencyCode: currency)}',
                      TextStyle(
                        color: scheme.onInverseSurface,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
                barGroups: [
                  BarChartGroupData(x: 0, barRods: [
                    BarChartRodData(
                      toY: income,
                      color: AppColors.income,
                      width: 44,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(12),
                      ),
                    ),
                  ]),
                  BarChartGroupData(x: 1, barRods: [
                    BarChartRodData(
                      toY: expense,
                      color: AppColors.expense,
                      width: 44,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(12),
                      ),
                    ),
                  ]),
                ],
                titlesData: FlTitlesData(
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 32,
                      getTitlesWidget: (value, meta) => Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.sm),
                        child: Text(
                          value == 0 ? 'Income' : 'Expenses',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 56,
                      getTitlesWidget: (value, meta) {
                        if (value == meta.max) return const SizedBox.shrink();
                        return Text(
                          NumberFormat.compact().format(value),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        );
                      },
                    ),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                ),
                borderData: FlBorderData(show: false),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: scheme.outlineVariant,
                    strokeWidth: 1,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              maxLines: 1,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportsSkeleton extends StatelessWidget {
  const _ReportsSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        Row(
          children: [
            Expanded(child: SkeletonBox(height: 116, radius: AppRadii.card)),
            SizedBox(width: AppSpacing.md),
            Expanded(child: SkeletonBox(height: 116, radius: AppRadii.card)),
          ],
        ),
        SizedBox(height: AppSpacing.md),
        SkeletonBox(height: 96, radius: AppRadii.card),
        SizedBox(height: AppSpacing.xxl),
        SkeletonBox(height: 260, radius: AppRadii.card),
      ],
    );
  }
}
