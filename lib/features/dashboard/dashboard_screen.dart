import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/avatar_provider.dart';
import '../../core/utils/currency_formatter.dart';
import '../../data/repositories/transaction_repository.dart';
import '../../providers/auth_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/contribution_provider.dart';
import '../../providers/dashboard_provider.dart';
import '../../providers/transaction_provider.dart';
import '../../widgets/add_transaction_sheet.dart';
import '../../widgets/summary_card.dart';
import '../../widgets/transaction_tile.dart';

import 'dart:io';
import 'package:in_app_update/in_app_update.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  @override
  void initState() {
    super.initState();
    if (Platform.isAndroid) {
      _checkForUpdate();
    }
  }

  Future<void> _checkForUpdate() async {
    try {
      final info = await InAppUpdate.checkForUpdate();
      if (info.updateAvailability == UpdateAvailability.updateAvailable) {
        if (info.immediateUpdateAllowed) {
          await InAppUpdate.performImmediateUpdate();
        } else if (info.flexibleUpdateAllowed) {
          await InAppUpdate.startFlexibleUpdate();
          await InAppUpdate.completeFlexibleUpdate();
        }
      }
    } catch (e) {
      // ignore
    }
  }

  static String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final summaryAsync = ref.watch(dashboardSummaryProvider);
    final recentAsync = ref.watch(transactionsStreamProvider);
    final user = ref.watch(authStateProvider).asData?.value;
    final profile = ref.watch(userProfileProvider).asData?.value;
    final name = profile?.displayName?.trim().isNotEmpty == true
        ? profile!.displayName!
        : (user?.displayName?.trim().isNotEmpty == true
            ? user!.displayName!
            : (user?.email ?? 'You'));
    final photoUrl = profile?.photoUrl ?? user?.photoURL;
    final initial = name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : '?';
    // Greet by first name only — "Good morning, Prathap" reads better than the
    // full display name or an email address.
    final shortName = name.contains('@') ? name.split('@').first : name.split(' ').first;

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab-dashboard',
        onPressed: () => showAddTransactionSheet(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add'),
      ),
      body: RefreshIndicator(
        color: AppColors.brand,
        onRefresh: () async {
          ref.invalidate(dashboardSummaryProvider);
        },
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            AppSliverHeader(
              eyebrow: _greeting(),
              title: shortName,
              actions: [
                _ProfileButton(photoUrl: photoUrl, initial: initial),
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
                  summaryAsync.when(
                    data: (summary) => _SummarySection(
                      summary: summary,
                      currency: settings.currency,
                    ),
                    loading: () => const _SummarySkeleton(),
                    error: (e, _) => AppErrorState(
                      message: "We couldn't load this month's summary.",
                      onRetry: () => ref.invalidate(dashboardSummaryProvider),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                  SectionHeader(
                    title: 'Recent activity',
                    actionLabel: 'See all',
                    onAction: () => context.go('/transactions'),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  recentAsync.when(
                    data: (txs) {
                      final recent = txs.take(5).toList();
                      if (recent.isEmpty) {
                        return AppCard(
                          padding: EdgeInsets.zero,
                          child: EmptyState(
                            icon: Icons.receipt_long_outlined,
                            title: 'No transactions yet',
                            message:
                                'Log your first income or expense and your balance will build from here.',
                            actionLabel: 'Add transaction',
                            onAction: () => showAddTransactionSheet(context),
                          ),
                        );
                      }
                      return AppCard(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm,
                          vertical: AppSpacing.sm,
                        ),
                        child: Column(
                          children: [
                            for (var i = 0; i < recent.length; i++) ...[
                              TransactionTile(
                                currency: settings.currency,
                                transaction: recent[i],
                                onTap: () => context.push(
                                  '/transaction/edit',
                                  extra: recent[i],
                                ),
                              ),
                              if (i != recent.length - 1)
                                Divider(
                                  height: 1,
                                  indent: AppSpacing.sm,
                                  endIndent: AppSpacing.sm,
                                  color: Theme.of(context).colorScheme.outlineVariant,
                                ),
                            ],
                          ],
                        ),
                      );
                    },
                    loading: () => const _ListSkeleton(),
                    error: (e, _) => AppErrorState(
                      message: "We couldn't load your recent activity.",
                      onRetry: () => ref.invalidate(transactionsStreamProvider),
                    ),
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

class _ProfileButton extends StatelessWidget {
  final String? photoUrl;
  final String initial;

  const _ProfileButton({required this.photoUrl, required this.initial});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasPhoto = photoUrl != null && photoUrl!.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.sm),
      child: Tooltip(
        message: 'Profile & settings',
        child: Material(
          color: scheme.surfaceContainer,
          shape: CircleBorder(side: BorderSide(color: scheme.outlineVariant)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => context.push('/settings'),
            child: Padding(
              padding: const EdgeInsets.all(5),
              child: CircleAvatar(
                radius: 17,
                backgroundColor: scheme.primary,
                backgroundImage: getAvatarProvider(photoUrl),
                child: hasPhoto
                    ? null
                    : Text(
                        initial,
                        style: TextStyle(
                          color: scheme.onPrimary,
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SummarySection extends ConsumerWidget {
  final DashboardSummary summary;
  final String currency;

  const _SummarySection({required this.summary, required this.currency});

  void _openFiltered(BuildContext context, WidgetRef ref, TransactionType type) {
    ref
        .read(transactionFilterProvider.notifier)
        .update(TransactionFilter(type: type));
    context.go('/transactions');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final monthLabel = DateFormat('MMMM yyyy').format(DateTime.now());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        BalanceHeroCard(
          label: monthLabel.toUpperCase(),
          amount: CurrencyFormatter.format(
            summary.balance,
            currencyCode: currency,
          ),
          subtitle: CurrencyFormatter.supportsWords(currency)
              ? CurrencyFormatter.inWords(summary.balance)
              : (summary.balance >= 0
                  ? 'Net saved this month'
                  : 'Overspent this month'),
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Expanded(
              child: SummaryCard(
                label: 'Income',
                value: CurrencyFormatter.format(
                  summary.totalIncome,
                  currencyCode: currency,
                ),
                caption: 'This month',
                icon: Icons.south_west_rounded,
                color: AppColors.income,
                onTap: () =>
                    _openFiltered(context, ref, TransactionType.income),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: SummaryCard(
                label: 'Expenses',
                value: CurrencyFormatter.format(
                  summary.totalExpense,
                  currencyCode: currency,
                ),
                caption: 'This month',
                icon: Icons.north_east_rounded,
                color: AppColors.expense,
                onTap: () =>
                    _openFiltered(context, ref, TransactionType.expense),
              ),
            ),
          ],
        ),
        if (summary.expenseByCategory.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xxl),
          SectionHeader(
            title: 'Where your money went',
            actionLabel: 'Reports',
            onAction: () => context.go('/reports'),
          ),
          const SizedBox(height: AppSpacing.md),
          AppCard(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: _ExpenseBreakdown(
              data: summary.expenseByCategory,
              currency: currency,
            ),
          ),
        ],
      ],
    );
  }
}

/// Donut + legend. The legend carries the amount and share for each category
/// so the chart never has to be decoded from colour alone.
class _ExpenseBreakdown extends StatelessWidget {
  final Map<String, double> data;
  final String currency;

  const _ExpenseBreakdown({required this.data, required this.currency});

  static const palette = [
    Color(0xFF279698),
    Color(0xFF0EA5E9),
    Color(0xFFF59E0B),
    Color(0xFFE11D48),
    Color(0xFF059669),
    Color(0xFFEA580C),
    Color(0xFF0F766E),
    Color(0xFF64748B),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final entries = data.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = entries.fold<double>(0, (sum, e) => sum + e.value);
    if (total <= 0) {
      return const EmptyState(
        icon: Icons.pie_chart_outline_rounded,
        title: 'No spending yet',
        message: 'Expenses you log this month will break down here.',
      );
    }

    // Keep the donut readable: top 6 categories, everything else rolled up.
    const maxSlices = 6;
    final visible = entries.take(maxSlices).toList();
    final restTotal = entries
        .skip(maxSlices)
        .fold<double>(0, (sum, e) => sum + e.value);
    final slices = [
      for (var i = 0; i < visible.length; i++)
        (visible[i].key, visible[i].value, palette[i % palette.length]),
      if (restTotal > 0)
        ('Other', restTotal, palette[maxSlices % palette.length]),
    ];

    return Column(
      children: [
        SizedBox(
          height: 180,
          child: Stack(
            alignment: Alignment.center,
            children: [
              PieChart(
                PieChartData(
                  sectionsSpace: 2,
                  centerSpaceRadius: 58,
                  startDegreeOffset: -90,
                  sections: [
                    for (final slice in slices)
                      PieChartSectionData(
                        value: slice.$2,
                        color: slice.$3,
                        radius: 22,
                        showTitle: false,
                      ),
                  ],
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Spent',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(height: 2),
                  SizedBox(
                    width: 104,
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
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        for (final slice in slices)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: slice.$3,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    slice.$1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  CurrencyFormatter.formatCompact(
                    slice.$2,
                    currencyCode: currency,
                  ),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                SizedBox(
                  width: 40,
                  child: Text(
                    '${(slice.$2 / total * 100).toStringAsFixed(0)}%',
                    textAlign: TextAlign.right,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
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
    return const Column(
      children: [
        SkeletonBox(height: 168, radius: AppRadii.hero),
        SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Expanded(child: SkeletonBox(height: 124, radius: AppRadii.card)),
            SizedBox(width: AppSpacing.md),
            Expanded(child: SkeletonBox(height: 124, radius: AppRadii.card)),
          ],
        ),
      ],
    );
  }
}

class _ListSkeleton extends StatelessWidget {
  const _ListSkeleton();

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        children: [
          for (var i = 0; i < 3; i++)
            Padding(
              padding: EdgeInsets.only(bottom: i == 2 ? 0 : AppSpacing.lg),
              child: const Row(
                children: [
                  SkeletonBox(width: 44, height: 44, radius: 14),
                  SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SkeletonBox(width: 120, height: 12, radius: 6),
                        SizedBox(height: AppSpacing.sm),
                        SkeletonBox(width: 80, height: 10, radius: 5),
                      ],
                    ),
                  ),
                  SkeletonBox(width: 64, height: 14, radius: 7),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
