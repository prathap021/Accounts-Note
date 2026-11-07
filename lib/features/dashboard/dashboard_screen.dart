import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/responsive.dart';
import '../../widgets/user_avatar.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/utils/greeting.dart';
import '../../data/repositories/transaction_repository.dart';
import '../../models/transaction_model.dart';
import '../../features/accounts/accounts_screen.dart';
import '../../providers/account_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/category_provider.dart';
import '../../providers/credit_card_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/sync_provider.dart';
import '../../providers/period_provider.dart';
import '../../providers/profile_provider.dart';
import '../../providers/dashboard_provider.dart';
import '../../providers/transaction_provider.dart';
import '../../widgets/add_transaction_sheet.dart';
import '../../widgets/credit_card_usage.dart';
import '../../widgets/summary_card.dart';
import '../../widgets/transaction_tile.dart';


/// One wedge of the dashboard donut.
typedef ExpenseSlice = ({String label, double amount, Color color});

/// Label for the wedge that rolls up everything past [kMaxDonutSlices].
///
/// Deliberately not "Other": that is a real default category, and using the
/// same word meant the legend could list "Other" twice with different values.
const kOtherSlicesLabel = 'Everything else';

/// How many categories get their own wedge before the rest are combined.
const kMaxDonutSlices = 6;

/// Builds the donut wedges, largest first, rolling the tail into one wedge so
/// the chart stays readable when a user has many categories.
List<ExpenseSlice> buildExpenseSlices(
  Map<String, double> byCategory, {
  required List<Color> palette,
  int maxSlices = kMaxDonutSlices,
}) {
  final entries = byCategory.entries.where((e) => e.value > 0).toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  if (entries.isEmpty) return const [];

  final visible = entries.take(maxSlices).toList();
  final restTotal =
      entries.skip(maxSlices).fold<double>(0, (sum, e) => sum + e.value);

  return [
    for (var i = 0; i < visible.length; i++)
      (
        label: visible[i].key,
        amount: visible[i].value,
        color: palette[i % palette.length],
      ),
    if (restTotal > 0)
      (
        label: kOtherSlicesLabel,
        amount: restTotal,
        color: palette[maxSlices % palette.length],
      ),
  ];
}

/// The entries the dashboard lists: today's only, newest first, capped.
///
/// The dashboard answers "what have I done today"; the Activity tab is where
/// history lives. [now] is injected so the day boundary can be tested without
/// depending on the wall clock.
List<TransactionModel> todaysActivity(
  List<TransactionModel> all, {
  required DateTime now,
  int limit = 5,
}) {
  final startOfDay = DateTime(now.year, now.month, now.day);
  return all
      .where((t) => !t.date.isBefore(startOfDay))
      .take(limit)
      .toList();
}

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final summary = ref.watch(dashboardSummaryProvider);
    final storeReady = ref.watch(localStoreReadyProvider);
    final recentAsync = ref.watch(allTransactionsStreamProvider);
    // A first sign-in on this phone: nothing local yet, and the user's
    // history is still downloading. Shimmer rather than an empty dashboard.
    final awaitingCloud = ref.watch(awaitingFirstCloudDataProvider);
    final user = ref.watch(authStateProvider).asData?.value;
    final profile = ref.watch(userProfileProvider).asData?.value;
    final name = resolveDisplayName(
      profileName: profile?.displayName,
      authName: user?.displayName,
      email: user?.email,
      fallback: 'You',
    );
    final photoUrl = profile?.photoUrl ?? user?.photoURL;
    final displayGreetingName = greetingName(name);
    final categories = ref.watch(categoryLookupProvider);
    final cards = ref.watch(creditCardLookupProvider);

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab-dashboard',
        onPressed: () => showAddTransactionSheet(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add'),
      ),
      body: RefreshIndicator(
        color: AppColors.brand,
        onRefresh: () => ref.read(syncManagerProvider).syncNow(),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            AppSliverHeader(
              eyebrow: greetingFor(DateTime.now()),
              title: displayGreetingName,
              actions: [
                _ProfileButton(
                  photoUrl: photoUrl,
                  name: name,
                  email: user?.email,
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
                  // Skeleton while the local box opens (milliseconds), and on
                  // a first sign-in until the cloud has been pulled down.
                  // With data on the device the summary is computed from
                  // Hive at once, with or without a network.
                  if (awaitingCloud)
                    const DashboardSummarySkeleton()
                  else
                  storeReady.when(
                    data: (_) => _SummarySection(
                      summary: summary,
                      currency: settings.currency,
                    ),
                    loading: () => const DashboardSummarySkeleton(),
                    error: (e, _) => AppErrorState(
                      message: "We couldn't open your local ledger.",
                      onRetry: () => ref.invalidate(localStoreReadyProvider),
                    ),
                  ),
                  const _AccountsSection(),
                  const _CreditCardSection(),
                  const SizedBox(height: AppSpacing.xxl),
                  SectionHeader(
                    title: "Today's activity",
                    subtitle: DateFormat('EEEE, MMM d').format(DateTime.now()),
                    actionLabel: 'See all',
                    onAction: () => context.go('/transactions'),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  if (awaitingCloud)
                    const _ListSkeleton()
                  else
                  recentAsync.when(
                    data: (txs) {
                      final recent =
                          todaysActivity(txs, now: DateTime.now());

                      if (recent.isEmpty) {
                        // An empty day and an empty ledger need different
                        // copy: telling someone with months of history that
                        // they have "no transactions yet" would be wrong.
                        final hasHistory = txs.isNotEmpty;
                        return AppCard(
                          padding: EdgeInsets.zero,
                          child: EmptyState(
                            icon: hasHistory
                                ? Icons.event_available_outlined
                                : Icons.receipt_long_outlined,
                            title: hasHistory
                                ? 'Nothing logged today'
                                : 'No transactions yet',
                            message: hasHistory
                                ? "Anything you add today shows up here. Earlier entries are under See all."
                                : 'Log your first income or expense and your balance will build from here.',
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
                                category: categories[recent[i].categoryId],
                                creditCard: cards[recent[i].creditCardId],
                                // Every row is from today, so the date would
                                // repeat on each one; the time is enough.
                                showDate: false,
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
                      onRetry: () => ref.invalidate(allTransactionsStreamProvider),
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
  final String name;
  final String? email;

  const _ProfileButton({
    required this.photoUrl,
    required this.name,
    required this.email,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

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
              child: UserAvatar(
                radius: 17,
                photoUrl: photoUrl,
                name: name,
                email: email,
                backgroundColor: scheme.primary,
                textStyle: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
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
    final month = ref.watch(dashboardMonthProvider);
    final isCurrent = ref.watch(isDashboardOnCurrentMonthProvider);
    final hidden = ref.watch(settingsProvider.select((s) => s.hideBalance));
    const masked = '••••••';
    String money(double v, {bool spaced = false}) => hidden
        ? masked
        : CurrencyFormatter.format(v, currencyCode: currency, spacedSymbol: spaced);
    final periodCaption = isCurrent ? 'This month' : month.label;

    // Earlier months' leftover sits beside the income it adds to (or the
    // spending a shortfall adds to), so the cards still add up to the balance.
    final carried = summary.carriedForward;
    String carriedCaption(double amount) =>
        hidden
            ? 'Includes carry-over'
            : '+ ${CurrencyFormatter.formatCompact(amount, currencyCode: currency)} carried over';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _MonthBar(),
        const SizedBox(height: AppSpacing.sm),
        BalanceHeroCard(
          // A past month shows where the balance stood when it ended.
          label: isCurrent ? 'Available balance' : 'Balance at month end',
          periodLabel: month.label,
          isPositive: summary.balance >= 0,
          amount: money(summary.balance, spaced: true),
          subtitle: hidden
              ? 'Hidden. Tap the eye to show amounts.'
              : CurrencyFormatter.supportsWords(currency)
              ? CurrencyFormatter.inWords(summary.balance)
              : (summary.balance >= 0
                  ? 'Available to spend'
                  : 'Spent more than you had'),
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Expanded(
              child: SummaryCard(
                label: 'Income',
                value: money(summary.totalIncome),
                caption: carried > 0 ? carriedCaption(carried) : periodCaption,
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
                value: money(summary.totalExpense),
                caption: carried < 0 ? carriedCaption(-carried) : periodCaption,
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

/// ‹ November 2026 › with the hide-amounts eye. Steps back through past
/// months; never forward past the current one.
class _MonthBar extends ConsumerWidget {
  const _MonthBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(dashboardMonthProvider);
    final isCurrent = ref.watch(isDashboardOnCurrentMonthProvider);
    final hidden = ref.watch(settingsProvider.select((s) => s.hideBalance));
    final months = ref.read(dashboardMonthOverrideProvider.notifier);
    final theme = Theme.of(context);

    return Row(
      children: [
        IconButton(
          tooltip: 'Previous month',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.chevron_left_rounded),
          onPressed: months.previous,
        ),
        Expanded(
          child: GestureDetector(
            onTap: isCurrent ? null : months.showCurrent,
            child: Column(
              children: [
                Text(
                  month.label,
                  key: const Key('dashboard-month'),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleSmall,
                ),
                if (!isCurrent)
                  Text(
                    'Tap to go back to this month',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
              ],
            ),
          ),
        ),
        IconButton(
          tooltip: 'Next month',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.chevron_right_rounded),
          onPressed: isCurrent ? null : months.next,
        ),
        IconButton(
          tooltip: hidden ? 'Show amounts' : 'Hide amounts',
          visualDensity: VisualDensity.compact,
          icon: Icon(
            hidden ? Icons.visibility_off_rounded : Icons.visibility_rounded,
          ),
          onPressed: () =>
              ref.read(settingsProvider.notifier).setHideBalance(!hidden),
        ),
      ],
    );
  }
}

/// Credit cards and what has been charged to each this month.
///
/// Separate from the cash cards above on purpose: a card swipe creates debt
/// rather than moving the user's own money, so mixing the two would make the
/// available balance read low and the card look free. Hidden entirely until
/// the user has added a card.
///
/// Live by construction — both providers recompute from the local Hive
/// ledger on every write, so a card expense lands here the moment it is
/// saved, online or off.
class _AccountsSection extends ConsumerWidget {
  const _AccountsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(accountsStreamProvider).asData?.value ?? const [];
    if (accounts.isEmpty) return const SizedBox.shrink();
    final balances = ref.watch(accountBalancesProvider);
    final currency = ref.watch(settingsProvider).currency;
    final hidden = ref.watch(settingsProvider).hideBalance;
    final total = accounts.fold<double>(
      0,
      (sum, a) => sum + (balances[a.id] ?? 0),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: AppSpacing.xxl),
        SectionHeader(
          title: 'Accounts',
          subtitle: hidden
              ? '•••••• in total'
              : '${CurrencyFormatter.format(total, currencyCode: currency)} in total',
          actionLabel: 'Manage',
          onAction: () => context.push('/accounts'),
        ),
        const SizedBox(height: AppSpacing.md),
        AppCard(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Column(
            children: [
              for (var i = 0; i < accounts.length; i++) ...[
                if (i > 0) const Divider(height: 1, indent: AppSpacing.md),
                hidden
                    ? ListTile(
                        leading: Icon(accounts[i].kind.icon),
                        title: Text(accounts[i].name),
                        trailing: const Text('••••••'),
                      )
                    : AccountBalanceTile(
                        account: accounts[i],
                        balance: balances[accounts[i].id] ?? 0,
                        currency: currency,
                        onTap: () => context.push('/accounts'),
                      ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _CreditCardSection extends ConsumerWidget {
  const _CreditCardSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cards = ref.watch(creditCardsStreamProvider).asData?.value ?? const [];
    if (cards.isEmpty) return const SizedBox.shrink();

    final spend = ref.watch(creditCardSpendProvider);
    final currency = ref.watch(settingsProvider).currency;
    final total = cards.fold<double>(
      0,
      (sum, card) => sum + (spend[card.id] ?? 0),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: AppSpacing.xxl),
        SectionHeader(
          title: 'Credit cards',
          subtitle:
              '${CurrencyFormatter.format(total, currencyCode: currency)} charged this month',
          actionLabel: 'Manage',
          onAction: () => context.push('/credit-cards'),
        ),
        const SizedBox(height: AppSpacing.md),
        AppCard(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Column(
            children: [
              for (var i = 0; i < cards.length; i++) ...[
                if (i > 0) const Divider(height: 1, indent: AppSpacing.md),
                CreditCardUsageTile(
                  card: cards[i],
                  spent: spend[cards[i].id] ?? 0,
                  currency: currency,
                  onTap: () => context.push('/credit-cards'),
                ),
              ],
            ],
          ),
        ),
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

    final total = data.values.fold<double>(0, (sum, v) => sum + v);
    if (total <= 0) {
      return const EmptyState(
        icon: Icons.pie_chart_outline_rounded,
        title: 'No spending yet',
        message: 'Expenses you log this month will break down here.',
      );
    }

    final slices = buildExpenseSlices(data, palette: palette);

    return Column(
      children: [
        SizedBox(
          height: 180.rh,
          child: Stack(
            alignment: Alignment.center,
            children: [
              PieChart(
                PieChartData(
                  sectionsSpace: 2,
                  centerSpaceRadius: 58.rr,
                  startDegreeOffset: -90,
                  sections: [
                    for (final slice in slices)
                      PieChartSectionData(
                        value: slice.amount,
                        color: slice.color,
                        radius: 22.rr,
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
                    width: 104.rw,
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
                  width: 10.rr,
                  height: 10.rr,
                  decoration: BoxDecoration(
                    color: slice.color,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    slice.label,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  CurrencyFormatter.formatCompact(
                    slice.amount,
                    currencyCode: currency,
                  ),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                SizedBox(
                  width: 40.rw,
                  child: Text(
                    '${(slice.amount / total * 100).toStringAsFixed(0)}%',
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

/// The balance card and the income / expense cards while there is nothing
/// to show yet, drawn in the shape of the real ones so the screen reads as
/// "loading", not "empty".
class DashboardSummarySkeleton extends StatelessWidget {
  const DashboardSummarySkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      key: const Key('dashboard-summary-skeleton'),
      children: [
        // Available balance: label, the large amount, a caption.
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.xl),
          decoration: BoxDecoration(
            color: AppColors.brand.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(AppRadii.hero),
            border: Border.all(color: AppColors.brand.withValues(alpha: 0.18)),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(width: 130, height: 14, radius: 7),
              SizedBox(height: AppSpacing.lg),
              SkeletonBox(width: 220, height: 40, radius: 12),
              SizedBox(height: AppSpacing.lg),
              SkeletonBox(width: 160, height: 14, radius: 7),
              SizedBox(height: AppSpacing.sm),
              SkeletonBox(width: 110, height: 12, radius: 6),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            for (final i in [0, 1]) ...[
              if (i == 1) const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainer,
                    borderRadius: BorderRadius.circular(AppRadii.card),
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                  // Income / expense: icon, label, amount.
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonBox(width: 36, height: 36, radius: 12),
                      SizedBox(height: AppSpacing.md),
                      SkeletonBox(width: 64, height: 12, radius: 6),
                      SizedBox(height: AppSpacing.sm),
                      SkeletonBox(width: 110, height: 22, radius: 8),
                    ],
                  ),
                ),
              ),
            ],
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
