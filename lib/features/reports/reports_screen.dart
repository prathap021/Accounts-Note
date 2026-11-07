import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/responsive.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/utils/money_month.dart';
import '../../core/utils/snackbar_helper.dart';
import '../../data/repositories/transaction_repository.dart';
import '../../providers/auth_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/sync_provider.dart';
import '../../providers/transaction_provider.dart';
import 'report_export.dart';
import 'report_insights.dart';
import 'report_charts.dart';

enum ReportRange { day, week, month, year, custom }

extension ReportRangeLabel on ReportRange {
  String get label => switch (this) {
        ReportRange.day => 'Day',
        ReportRange.week => 'Week',
        ReportRange.month => 'Month',
        ReportRange.year => 'Year',
        ReportRange.custom => 'Custom',
      };

  String get caption => switch (this) {
        ReportRange.day => 'Today so far',
        ReportRange.week => 'This week so far',
        ReportRange.month => 'This month so far',
        ReportRange.year => 'This year so far',
        ReportRange.custom => 'Custom range',
      };
}

/// The period a report covers: one of the presets, or days the user picked
/// on the calendar.
class ReportPeriod {
  final ReportRange range;

  /// The first and last day picked, as dates. Kept after switching back to a
  /// preset, so the calendar reopens on the last custom range.
  final DateTimeRange? custom;

  const ReportPeriod(this.range, {this.custom});

  bool get isCustom => range == ReportRange.custom && custom != null;

  /// The exact window to total: presets run from the start of the week,
  /// month or year to now; a custom range covers its first and last days in
  /// full.
  DateTimeRange resolve([DateTime? now, int monthStartDay = 1]) {
    final n = now ?? DateTime.now();
    switch (range) {
      case ReportRange.day:
        return DateTimeRange(start: DateTime(n.year, n.month, n.day), end: n);
      case ReportRange.week:
        final start = n.subtract(Duration(days: n.weekday - 1));
        return DateTimeRange(
            start: DateTime(start.year, start.month, start.day), end: n);
      case ReportRange.month:
        // The budgeting month, which may start on a salary day.
        final month = MoneyMonth.containing(n, monthStartDay);
        return DateTimeRange(start: month.start, end: n);
      case ReportRange.year:
        return DateTimeRange(start: DateTime(n.year, 1, 1), end: n);
      case ReportRange.custom:
        final picked = custom;
        if (picked == null) {
          return const ReportPeriod(ReportRange.month).resolve(n);
        }
        final s = picked.start;
        final e = picked.end;
        return DateTimeRange(
          start: DateTime(s.year, s.month, s.day),
          end: DateTime(e.year, e.month, e.day, 23, 59, 59, 999),
        );
    }
  }
}

class _ReportPeriodNotifier extends Notifier<ReportPeriod> {
  @override
  ReportPeriod build() => const ReportPeriod(ReportRange.month);

  void setPreset(ReportRange r) =>
      state = ReportPeriod(r, custom: state.custom);

  void setCustom(DateTimeRange picked) =>
      state = ReportPeriod(ReportRange.custom, custom: picked);
}

final reportPeriodProvider =
    NotifierProvider<_ReportPeriodNotifier, ReportPeriod>(
  _ReportPeriodNotifier.new,
);

class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});

  /// Opens the calendar on the current period. Cancel leaves the report as
  /// it was; Save switches it to the picked days.
  ///
  /// The calendar reaches back to the oldest transaction (and at least to
  /// 2000), so any past period can be reported on.
  Future<void> _pickDates(
    BuildContext context,
    WidgetRef ref,
    DateTimeRange current,
  ) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final all =
        ref.read(offlineTransactionRepositoryProvider).currentTransactions();
    // Newest first, so the last entry is the oldest.
    final oldest = all.isEmpty ? null : all.last.date;
    final newest = all.isEmpty ? null : all.first.date;
    var first = DateTime(2000);
    if (oldest != null && oldest.isBefore(first)) {
      first = DateTime(oldest.year, oldest.month, oldest.day);
    }
    // Entries can be dated ahead (a bill due next week), so allow those.
    var last = today;
    if (newest != null && newest.isAfter(today)) {
      last = DateTime(newest.year, newest.month, newest.day);
    }

    DateTime clamp(DateTime d) => d.isBefore(first)
        ? first
        : d.isAfter(last)
            ? last
            : d;

    final picked = await showDateRangePicker(
      context: context,
      firstDate: first,
      lastDate: last,
      initialDateRange: DateTimeRange(
        start: clamp(current.start),
        end: clamp(current.end),
      ),
      helpText: 'Select report period',
      // Calendar mode shows saveText; typing the dates shows confirmText.
      saveText: 'Generate',
      confirmText: 'Generate',
    );
    if (picked != null) {
      ref.read(reportPeriodProvider.notifier).setCustom(picked);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final period = ref.watch(reportPeriodProvider);
    final range = period.isCustom ? ReportRange.custom : period.range;
    final uid = ref.watch(currentUidProvider);
    final currency = ref.watch(settingsProvider).currency;
    final dateRange = period.resolve(
      null,
      ref.watch(settingsProvider).monthStartDay,
    );
    final dateFormat =
        period.isCustom ? DateFormat('d MMM yyyy') : DateFormat('MMM d');
    final periodLabel =
        '${dateFormat.format(dateRange.start)} – ${dateFormat.format(dateRange.end)}';

    // Totals from the local store: correct offline, and refreshed the moment
    // a transaction is saved.
    ref.watch(allTransactionsStreamProvider);
    final sums = ref.watch(offlineTransactionRepositoryProvider).sumByType(
          start: dateRange.start,
          end: dateRange.end,
        );
    final income = (sums[TransactionType.income] ?? 0).toDouble();
    final expense = (sums[TransactionType.expense] ?? 0).toDouble();
    final insights = ReportInsights.build(
      ref.read(offlineTransactionRepositoryProvider).currentTransactions(),
      dateRange,
    );

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          AppSliverHeader(
            eyebrow: range.caption,
            title: 'Reports',
            actions: [
              HeaderAction(
                icon: Icons.ios_share_rounded,
                tooltip: 'Export report',
                onTap: uid == null
                    ? null
                    : () => _export(
                          context,
                          ref,
                          dateRange,
                          periodLabel,
                          currency,
                        ),
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
                  onSelectionChanged: (s) {
                    final picked = s.first;
                    if (picked == ReportRange.custom) {
                      // Custom stays unselected until dates are chosen, so
                      // cancelling the calendar leaves the report as it was.
                      _pickDates(context, ref, period.custom ?? dateRange);
                    } else {
                      ref.read(reportPeriodProvider.notifier).setPreset(picked);
                    }
                  },
                ),
                const SizedBox(height: AppSpacing.sm),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    key: const Key('report-period'),
                    onPressed: () => _pickDates(context, ref, dateRange),
                    style: TextButton.styleFrom(
                      foregroundColor:
                          Theme.of(context).colorScheme.onSurfaceVariant,
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xs,
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: const Icon(Icons.calendar_month_rounded, size: 18),
                    label: Text(
                      periodLabel,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                if (uid == null)
                  const SizedBox.shrink()
                else if (income == 0 && expense == 0)
                  AppCard(
                    padding: EdgeInsets.zero,
                    child: period.isCustom
                        ? EmptyState(
                            icon: Icons.event_busy_rounded,
                            title: 'Nothing in this period',
                            message:
                                'No transactions were logged from $periodLabel. Tap the dates to choose another period.',
                          )
                        : const EmptyState(
                            icon: Icons.insights_outlined,
                            title: 'Nothing to report yet',
                            message:
                                'Once you log transactions in this period, your totals and chart appear here.',
                          ),
                  )
                else
                  _ReportBody(
                    income: income,
                    expense: expense,
                    currency: currency,
                    insights: insights,
                    onCategoryTap: (c, type) => _openCategory(
                      context,
                      ref,
                      dateRange,
                      c,
                      type,
                    ),
                  ),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  /// Lists the period's entries in [category] on the Activity tab.
  void _openCategory(
    BuildContext context,
    WidgetRef ref,
    DateTimeRange range,
    CategoryTotal category,
    TransactionType type,
  ) {
    ref
        .read(transactionFilterProvider.notifier)
        .update(
          TransactionFilter(
            startDate: range.start,
            endDate: range.end,
            type: type,
            categoryId: category.categoryId,
          ),
        );
    context.go('/transactions');
  }

  /// Asks which file type, then builds the report for the period on screen
  /// and opens the share sheet.
  Future<void> _export(
    BuildContext context,
    WidgetRef ref,
    DateTimeRange range,
    String periodLabel,
    String currency,
  ) async {
    final data = ReportData(
      range: range,
      periodLabel: periodLabel,
      currency: currency,
      transactions:
          ref.read(offlineTransactionRepositoryProvider).currentTransactions(),
    );
    if (data.isEmpty) {
      SnackbarHelper.showError(context, 'Nothing to export in this period.');
      return;
    }
    final format = await showModalBottomSheet<ReportFormat>(
      context: context,
      builder: (ctx) => _ExportSheet(
        periodLabel: periodLabel,
        count: data.transactions.length,
      ),
    );
    if (format == null || !context.mounted) return;
    try {
      await ReportExporter.share(data, format);
    } catch (e) {
      if (context.mounted) {
        SnackbarHelper.showError(
          context,
          'Could not create the ${format.label.toLowerCase()}. Please try again.',
        );
      }
    }
  }
}

/// Picks the export format.
class _ExportSheet extends StatelessWidget {
  const _ExportSheet({required this.periodLabel, required this.count});

  final String periodLabel;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget option(ReportFormat format, IconData icon, String detail) =>
        ListTile(
          leading: Icon(icon, color: theme.colorScheme.primary),
          title: Text(format.label),
          subtitle: Text(detail),
          onTap: () => Navigator.pop(context, format),
        );

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
                AppSpacing.sm,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Export report', style: theme.textTheme.titleLarge),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    '$periodLabel · $count '
                    '${count == 1 ? 'transaction' : 'transactions'}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            option(ReportFormat.pdf, Icons.picture_as_pdf_rounded,
                'Totals and every entry, ready to print or share'),
            option(ReportFormat.excel, Icons.table_chart_rounded,
                'A summary sheet and a transactions sheet (.xlsx)'),
            option(ReportFormat.csv, Icons.description_outlined,
                'Plain rows for any spreadsheet app'),
            const SizedBox(height: AppSpacing.md),
          ],
        ),
      ),
    );
  }
}

class _ReportBody extends StatelessWidget {
  final double income;
  final double expense;
  final String currency;
  final ReportInsights insights;
  final void Function(CategoryTotal, TransactionType) onCategoryTap;

  const _ReportBody({
    required this.income,
    required this.expense,
    required this.currency,
    required this.insights,
    required this.onCategoryTap,
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
            height: 230.rh,
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
                      width: 44.rw,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(12),
                      ),
                    ),
                  ]),
                  BarChartGroupData(x: 1, barRods: [
                    BarChartRodData(
                      toY: expense,
                      color: AppColors.expense,
                      width: 44.rw,
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
        if (insights.spending.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xxl),
          const SectionHeader(
            title: 'Spending by category',
            subtitle: 'Tap a category to see its entries',
          ),
          const SizedBox(height: AppSpacing.md),
          CategoryBreakdownCard(
            key: const Key('report-spending'),
            totals: insights.spending,
            currency: currency,
            onTap: (c) => onCategoryTap(c, TransactionType.expense),
          ),
        ],
        if (insights.trend.length > 1) ...[
          const SizedBox(height: AppSpacing.xxl),
          SectionHeader(
            title: 'Trend',
            subtitle: switch (insights.bucket) {
              TrendBucket.day => 'Day by day',
              TrendBucket.week => 'Week by week',
              TrendBucket.month => 'Month by month',
            },
          ),
          const SizedBox(height: AppSpacing.md),
          TrendChartCard(points: insights.trend, currency: currency),
        ],
        if (insights.earning.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xxl),
          const SectionHeader(title: 'Income by category'),
          const SizedBox(height: AppSpacing.md),
          CategoryBreakdownCard(
            key: const Key('report-earning'),
            totals: insights.earning,
            currency: currency,
            showChart: false,
            color: AppColors.income,
            onTap: (c) => onCategoryTap(c, TransactionType.income),
          ),
        ],
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
