import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/currency_formatter.dart';
import 'report_insights.dart';

/// Fallback colours, by rank, for a category the user no longer has. Each
/// of the user's own categories is drawn in its own colour.
const kCategoryPalette = [
  Color(0xFF279698),
  Color(0xFF0EA5E9),
  Color(0xFFF59E0B),
  Color(0xFFE11D48),
  Color(0xFF059669),
  Color(0xFFEA580C),
  Color(0xFF64748B),
];

/// A donut of the categories plus a row per category with its amount and
/// share. Tapping a row calls [onTap] with it.
///
/// Every slice and row is one of the user's categories, in that category's
/// colour ([categoryColors], by id); nothing is grouped into a made-up
/// "other" slice.
class CategoryBreakdownCard extends StatelessWidget {
  const CategoryBreakdownCard({
    super.key,
    required this.totals,
    required this.currency,
    required this.onTap,
    this.showChart = true,
    this.color,
    this.categoryColors = const {},
  });

  final List<CategoryTotal> totals;
  final String currency;
  final ValueChanged<CategoryTotal> onTap;
  final bool showChart;

  /// One colour for every row; otherwise each takes its category's colour.
  final Color? color;

  /// The user's category colours, by category id.
  final Map<String, Color> categoryColors;

  Color _colorAt(int i) =>
      color ??
      categoryColors[totals[i].categoryId] ??
      kCategoryPalette[i % kCategoryPalette.length];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Column(
        children: [
          if (showChart)
            _ExpenseDonut(
              totals: totals,
              colors: [for (var i = 0; i < totals.length; i++) _colorAt(i)],
              currency: currency,
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

/// A thick donut of the categories with rounded, spaced segments and the
/// total in the middle. Tapping a segment pops it out and shows its share.
class _ExpenseDonut extends StatefulWidget {
  const _ExpenseDonut({
    required this.totals,
    required this.colors,
    required this.currency,
  });

  final List<CategoryTotal> totals;
  final List<Color> colors;
  final String currency;

  @override
  State<_ExpenseDonut> createState() => _ExpenseDonutState();
}

class _ExpenseDonutState extends State<_ExpenseDonut> {
  int? _touched;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final totals = widget.totals;
    final total = totals.fold<double>(0, (s, c) => s + c.amount);
    final touched = _touched != null && _touched! < totals.length
        ? _touched
        : null;

    // "₹27,488" large, ".00" lighter.
    final formatted = CurrencyFormatter.format(
      total,
      currencyCode: widget.currency,
    );
    final dot = formatted.lastIndexOf('.');
    final whole = dot < 0 ? formatted : formatted.substring(0, dot);
    final fraction = dot < 0 ? '' : formatted.substring(dot);

    return SizedBox(
      key: const Key('report-donut'),
      height: 250,
      child: Stack(
        alignment: Alignment.center,
        children: [
          PieChart(
            PieChartData(
              sectionsSpace: totals.length == 1 ? 0 : 5,
              centerSpaceRadius: 72,
              startDegreeOffset: -90,
              pieTouchData: PieTouchData(
                touchCallback: (event, response) {
                  if (event is! FlTapUpEvent) return;
                  final i = response?.touchedSection?.touchedSectionIndex;
                  setState(
                    () => _touched = (i == null || i < 0 || i == _touched)
                        ? null
                        : i,
                  );
                },
              ),
              sections: [
                for (var i = 0; i < totals.length; i++)
                  PieChartSectionData(
                    value: totals[i].amount,
                    color: widget.colors[i],
                    radius: i == touched ? 40 : 32,
                    cornerRadius: 10,
                    showTitle: false,
                    badgeWidget: i == touched
                        ? _ShareBadge(share: totals[i].share)
                        : null,
                    badgePositionPercentageOffset: 1.08,
                  ),
              ],
            ),
            duration: const Duration(milliseconds: 250),
          ),
          IgnorePointer(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  touched == null ? 'Total expenses' : totals[touched].name,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                SizedBox(
                  width: 128,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: touched != null
                        ? Text(
                            CurrencyFormatter.format(
                              totals[touched].amount,
                              currencyCode: widget.currency,
                            ),
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          )
                        : Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(text: whole),
                                TextSpan(
                                  text: fraction,
                                  style: TextStyle(
                                    color: scheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The dark "31%" bubble on a tapped segment.
class _ShareBadge extends StatelessWidget {
  const _ShareBadge({required this.share});

  final double share;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: AppColors.ink,
      borderRadius: BorderRadius.circular(AppRadii.pill),
    ),
    child: Text(
      '${(share * 100).round()}%',
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: Colors.white,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
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
                          borderRadius: BorderRadius.vertical(
                            top: Radius.circular(barWidth / 2),
                          ),
                        ),
                        BarChartRodData(
                          toY: points[i].expense,
                          color: AppColors.coral,
                          width: barWidth,
                          borderRadius: BorderRadius.vertical(
                            top: Radius.circular(barWidth / 2),
                          ),
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
              _Legend(color: AppColors.coral, label: 'Spent'),
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
