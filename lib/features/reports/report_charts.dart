import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/currency_formatter.dart';
import 'report_insights.dart';

/// Colours for category slices, in rank order. The legend rows carry the
/// name, amount and share, so nothing is read from colour alone.
const kCategoryPalette = [
  Color(0xFF279698),
  Color(0xFF0EA5E9),
  Color(0xFFF59E0B),
  Color(0xFFE11D48),
  Color(0xFF059669),
  Color(0xFFEA580C),
  Color(0xFF64748B),
];

/// Slices shown on the donut before the rest are grouped.
const _maxSlices = 6;

/// A donut of the categories plus a row per category with its amount and
/// share. Tapping a row calls [onTap] with it.
class CategoryBreakdownCard extends StatelessWidget {
  const CategoryBreakdownCard({
    super.key,
    required this.totals,
    required this.currency,
    required this.onTap,
    this.showChart = true,
    this.color,
  });

  final List<CategoryTotal> totals;
  final String currency;
  final ValueChanged<CategoryTotal> onTap;
  final bool showChart;

  /// One colour for every row; otherwise each takes its slice colour.
  final Color? color;

  Color _colorAt(int i) =>
      color ??
      kCategoryPalette[math.min(i, _maxSlices) % kCategoryPalette.length];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final total = totals.fold<double>(0, (s, c) => s + c.amount);
    final rest = totals
        .skip(_maxSlices)
        .fold<double>(0, (s, c) => s + c.amount);

    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Column(
        children: [
          if (showChart)
            SizedBox(
              height: 170,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  PieChart(
                    PieChartData(
                      sectionsSpace: 2,
                      centerSpaceRadius: 54,
                      startDegreeOffset: -90,
                      sections: [
                        for (
                          var i = 0;
                          i < math.min(totals.length, _maxSlices);
                          i++
                        )
                          PieChartSectionData(
                            value: totals[i].amount,
                            color: _colorAt(i),
                            radius: 20,
                            showTitle: false,
                          ),
                        if (rest > 0)
                          PieChartSectionData(
                            value: rest,
                            color: _colorAt(_maxSlices),
                            radius: 20,
                            showTitle: false,
                          ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 100,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        CurrencyFormatter.formatCompact(
                          total,
                          currencyCode: currency,
                        ),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          for (var i = 0; i < totals.length; i++)
            InkWell(
              key: Key('report-category-${totals[i].name}'),
              onTap: () => onTap(totals[i]),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.sm,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: _colorAt(i),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            totals[i].name,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          '${(totals[i].share * 100).toStringAsFixed(0)}%',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Text(
                          CurrencyFormatter.format(
                            totals[i].amount,
                            currencyCode: currency,
                          ),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 18,
                          color: scheme.onSurfaceVariant,
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: totals[i].share,
                        minHeight: 4,
                        color: _colorAt(i),
                        backgroundColor: scheme.surfaceContainerHighest,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Income and spending per day, week or month across the period.
class TrendChartCard extends StatelessWidget {
  const TrendChartCard({
    super.key,
    required this.points,
    required this.currency,
  });

  final List<TrendPoint> points;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final maxY = points.fold<double>(
      0,
      (m, p) => math.max(m, math.max(p.income, p.expense)),
    );
    // Room for about six labels along the bottom.
    final every = math.max(1, (points.length / 6).ceil());
    final barWidth = points.length > 20
        ? 3.0
        : (points.length > 8 ? 6.0 : 12.0);

    return AppCard(
      key: const Key('report-trend'),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.xl,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: Column(
        children: [
          SizedBox(
            height: 200,
            child: BarChart(
              BarChartData(
                maxY: maxY <= 0 ? 1 : maxY * 1.15,
                alignment: BarChartAlignment.spaceAround,
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (_) => scheme.inverseSurface,
                    getTooltipItem: (group, _, rod, rodIndex) => BarTooltipItem(
                      '${points[group.x].label}\n'
                      '${rodIndex == 0 ? 'Income' : 'Spent'} '
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
                  for (var i = 0; i < points.length; i++)
                    BarChartGroupData(
                      x: i,
                      barsSpace: 1,
                      barRods: [
                        BarChartRodData(
                          toY: points[i].income,
                          color: AppColors.income,
                          width: barWidth,
                        ),
                        BarChartRodData(
                          toY: points[i].expense,
                          color: AppColors.expense,
                          width: barWidth,
                        ),
                      ],
                    ),
                ],
                titlesData: FlTitlesData(
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      getTitlesWidget: (value, meta) {
                        final i = value.toInt();
                        if (i % every != 0 || i >= points.length) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: AppSpacing.sm),
                          child: Text(
                            points[i].label,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 48,
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
                  getDrawingHorizontalLine: (_) =>
                      FlLine(color: scheme.outlineVariant, strokeWidth: 1),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _Legend(color: AppColors.income, label: 'Income'),
              SizedBox(width: AppSpacing.lg),
              _Legend(color: AppColors.expense, label: 'Spent'),
            ],
          ),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
      const SizedBox(width: AppSpacing.xs),
      Text(label, style: Theme.of(context).textTheme.labelSmall),
    ],
  );
}
