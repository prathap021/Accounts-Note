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
import '../../providers/auth_provider.dart';
import '../../providers/transaction_provider.dart';

enum ReportRange { week, month, year }

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
    final dateRange = _rangeFor(range);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: Column(
        children: [
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Reports',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                          ),
                    ),
                  ),
                  IconButton.filledTonal(
                    icon: const Icon(Icons.ios_share_rounded),
                    tooltip: 'Export CSV',
                    onPressed: uid == null
                        ? null
                        : () => _exportCsv(context, ref, uid, dateRange),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: SegmentedButton<ReportRange>(
              segments: const [
                ButtonSegment(value: ReportRange.week, label: Text('Week')),
                ButtonSegment(value: ReportRange.month, label: Text('Month')),
                ButtonSegment(value: ReportRange.year, label: Text('Year')),
              ],
              selected: {range},
              onSelectionChanged: (s) =>
                  ref.read(reportRangeProvider.notifier).set(s.first),
            ),
          ),
          Expanded(
            child: uid == null
                ? const SizedBox.shrink()
                : FutureBuilder(
                    future: ref.read(transactionRepositoryProvider).sumByType(
                          uid,
                          start: dateRange.start,
                          end: dateRange.end,
                        ),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
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
                      final net = income - expense;

                      return ListView(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                        children: [
                          Container(
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: scheme.surfaceContainer,
                              borderRadius: BorderRadius.circular(22),
                              border: Border.all(
                                color: scheme.outlineVariant
                                    .withValues(alpha: 0.35),
                              ),
                            ),
                            child: Column(
                              children: [
                                _StatRow(
                                    label: 'Income',
                                    value: income,
                                    color: AppColors.income),
                                Divider(
                                  color: scheme.outlineVariant
                                      .withValues(alpha: 0.35),
                                ),
                                _StatRow(
                                    label: 'Expenses',
                                    value: expense,
                                    color: AppColors.expense),
                                Divider(
                                  color: scheme.outlineVariant
                                      .withValues(alpha: 0.35),
                                ),
                                _StatRow(
                                  label: 'Net savings',
                                  value: net,
                                  color: net >= 0
                                      ? AppColors.income
                                      : AppColors.expense,
                                  bold: true,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          Container(
                            height: 240,
                            padding: const EdgeInsets.fromLTRB(12, 20, 12, 12),
                            decoration: BoxDecoration(
                              color: scheme.surfaceContainer,
                              borderRadius: BorderRadius.circular(22),
                              border: Border.all(
                                color: scheme.outlineVariant
                                    .withValues(alpha: 0.35),
                              ),
                            ),
                            child: BarChart(
                              BarChartData(
                                barGroups: [
                                  BarChartGroupData(x: 0, barRods: [
                                    BarChartRodData(
                                      toY: income,
                                      color: AppColors.income,
                                      width: 36,
                                      borderRadius: const BorderRadius.vertical(
                                          top: Radius.circular(10)),
                                    ),
                                  ]),
                                  BarChartGroupData(x: 1, barRods: [
                                    BarChartRodData(
                                      toY: expense,
                                      color: AppColors.expense,
                                      width: 36,
                                      borderRadius: const BorderRadius.vertical(
                                          top: Radius.circular(10)),
                                    ),
                                  ]),
                                ],
                                titlesData: FlTitlesData(
                                  bottomTitles: AxisTitles(
                                    sideTitles: SideTitles(
                                      showTitles: true,
                                      getTitlesWidget: (value, meta) => Text(
                                        value == 0 ? 'Income' : 'Expense',
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelMedium,
                                      ),
                                    ),
                                  ),
                                  leftTitles: const AxisTitles(
                                    sideTitles: SideTitles(
                                        showTitles: true, reservedSize: 48),
                                  ),
                                  topTitles: const AxisTitles(
                                      sideTitles: SideTitles(showTitles: false)),
                                  rightTitles: const AxisTitles(
                                      sideTitles: SideTitles(showTitles: false)),
                                ),
                                borderData: FlBorderData(show: false),
                                gridData: FlGridData(
                                  show: true,
                                  drawVerticalLine: false,
                                  getDrawingHorizontalLine: (value) => FlLine(
                                    color: scheme.outlineVariant
                                        .withValues(alpha: 0.35),
                                    strokeWidth: 1,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
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
    final messenger = ScaffoldMessenger.of(context);
    final result = await ref
        .read(transactionRepositoryProvider)
        .fetchPage(uid: uid, pageSize: 1000);
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
      failure: (f) => messenger
          .showSnackBar(SnackBar(content: Text('Export failed: ${f.message}'))),
    );
  }
}

class _StatRow extends StatelessWidget {
  final String label;
  final double value;
  final Color color;
  final bool bold;
  const _StatRow({
    required this.label,
    required this.value,
    required this.color,
    this.bold = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
            ),
          ),
          Text(
            CurrencyFormatter.format(value),
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
