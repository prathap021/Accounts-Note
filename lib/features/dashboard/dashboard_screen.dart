import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/constants/app_constants.dart';
import '../../core/constants/category_icons.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/responsive.dart';
import '../../widgets/user_avatar.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/utils/greeting.dart';
import '../../data/repositories/transaction_repository.dart';
import '../../models/category_model.dart';
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
import '../../widgets/transaction_tile.dart';


/// One wedge of the dashboard donut: one of the user's own categories.
typedef ExpenseSlice = ({String label, double amount, Color color});

/// Builds the donut wedges, largest first: one per category the user spent
/// in, each in the colour [colorOf] gives it (the category's own colour, so
/// the chart matches the icons everywhere else).
///
/// Nothing is rolled up into a made-up "everything else" wedge: every wedge
/// and every legend row is a category the user actually has. A long legend
/// is shortened on screen instead (see [_ExpenseBreakdown]).
List<ExpenseSlice> buildExpenseSlices(
  Map<String, double> byCategory, {
  required Color Function(String category, int rank) colorOf,
}) {
  final entries = byCategory.entries.where((e) => e.value > 0).toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return [
    for (var i = 0; i < entries.length; i++)
      (
        label: entries[i].key,
        amount: entries[i].value,
        color: colorOf(entries[i].key, i),
      ),
  ];
}

/// One day's cash spending, for the dashboard's 7-day chart.
typedef DaySpend = ({DateTime day, double amount});

/// What was spent on each of the seven days ending [lastDay], oldest first.
/// Card charges are left out, as everywhere on the dashboard: they are debt
/// on the card, not money that has left the user's pocket.
List<DaySpend> lastSevenDaysSpending(
  Iterable<TransactionModel> all, {
  required DateTime lastDay,
}) {
  final days = [
    for (var i = 6; i >= 0; i--)
      DateTime(lastDay.year, lastDay.month, lastDay.day - i),
  ];
  final totals = {for (final d in days) d: 0.0};
  for (final t in all) {
    if (t.type != TransactionType.expense || t.isOnCard || t.isDeleted) {
      continue;
    }
    final day = DateTime(t.date.year, t.date.month, t.date.day);
    final sum = totals[day];
    if (sum != null) totals[day] = sum + t.amount;
  }
  return [for (final d in days) (day: d, amount: totals[d]!)];
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
    final scheme = Theme.of(context).colorScheme;

    // Skeleton while the local box opens (milliseconds), and on a first
    // sign-in until the cloud has been pulled down. With data on the device
    // the summary is computed from Hive at once, with or without a network.
    final ledger = awaitingCloud
        ? _Ledger.loading
        : storeReady.when(
            data: (_) => _Ledger.ready,
            loading: () => _Ledger.loading,
            error: (_, _) => _Ledger.failed,
          );

    return Scaffold(
      // White and airy: Home sits on the card colour rather than the grey
      // canvas, with soft tinted panels instead of boxes.
      backgroundColor: scheme.surfaceContainerLowest,
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab-dashboard',
        onPressed: () => showAddTransactionSheet(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add'),
      ),
      body: RefreshIndicator(
        color: scheme.primary,
        onRefresh: () => ref.read(syncManagerProvider).syncNow(),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            AppSliverHeader(
              eyebrow: greetingFor(DateTime.now()),
              title: displayGreetingName,
              backgroundColor: scheme.surfaceContainerLowest,
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
                  switch (ledger) {
                    _Ledger.ready => _BalanceBlock(
                      summary: summary,
                      currency: settings.currency,
                    ),
                    _Ledger.loading => const DashboardSummarySkeleton(),
                    _Ledger.failed => AppErrorState(
                      message: "We couldn't open your local ledger.",
                      onRetry: () => ref.invalidate(localStoreReadyProvider),
                    ),
                  },
                  // Order: where the money went, accounts and cards, then the
                  // last 7 days and today's entries at the end.
                  if (ledger == _Ledger.ready)
                    _WhereItWent(summary: summary, currency: settings.currency),
                  const _AccountsSection(),
                  const _CreditCardSection(),
                  // The week chart waits for a first entry: for a new user an
                  // empty chart is noise, and "No transactions yet" with its
                  // Add button is what matters.
                  if (ledger == _Ledger.ready &&
                      (recentAsync.asData?.value.isNotEmpty ?? false)) ...[
                    const SizedBox(height: AppSpacing.xxl),
                    _WeekSpending(currency: settings.currency),
                  ],
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
                        final recent = todaysActivity(txs, now: DateTime.now());

                        if (recent.isEmpty) {
                          // An empty day and an empty ledger need different
                          // copy: telling someone with months of history that
                          // they have "no transactions yet" would be wrong.
                          final hasHistory = txs.isNotEmpty;
                          return _Panel(
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
                        return _Panel(
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
                                  // Every row is from today, so the date
                                  // would repeat on each one; the time is
                                  // enough.
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
                                    color: scheme.outlineVariant,
                                  ),
                              ],
                            ],
                          ),
                        );
                      },
                      loading: () => const _ListSkeleton(),
                      error: (e, _) => AppErrorState(
                        message: "We couldn't load your recent activity.",
                        onRetry: () =>
                            ref.invalidate(allTransactionsStreamProvider),
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

/// Where the local ledger stands, for the dashboard's loading states.
enum _Ledger { loading, ready, failed }

/// A soft tinted panel: Home's way of grouping things on its white page
/// without the weight of a boxed, shadowed card.
class _Panel extends StatelessWidget {
  const _Panel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  static Color tintOf(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Theme.of(context).brightness == Brightness.dark
        ? scheme.surfaceContainer
        : Color.alphaBlend(
            scheme.primary.withValues(alpha: 0.035),
            scheme.surfaceContainerLow,
          );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: tintOf(context),
        borderRadius: BorderRadius.circular(AppRadii.card),
      ),
      child: child,
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
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.sm),
      child: Tooltip(
        message: 'Profile & settings',
        child: Material(
          color: scheme.surfaceContainerLowest,
          elevation: dark ? 0 : 2,
          shadowColor: Colors.black.withValues(alpha: 0.25),
          shape: CircleBorder(
            side: BorderSide(
              color: dark ? scheme.outlineVariant : Colors.transparent,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => context.push('/settings'),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: UserAvatar(
                radius: 19,
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

/// The month, the balance in large type, and the Expenses / Income pills.
class _BalanceBlock extends ConsumerWidget {
  final DashboardSummary summary;
  final String currency;

  const _BalanceBlock({required this.summary, required this.currency});

  void _openFiltered(BuildContext context, WidgetRef ref, TransactionType type) {
    ref
        .read(transactionFilterProvider.notifier)
        .update(TransactionFilter(type: type));
    context.go('/transactions');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final month = ref.watch(dashboardMonthProvider);
    final isCurrent = ref.watch(isDashboardOnCurrentMonthProvider);
    final hidden = ref.watch(settingsProvider.select((s) => s.hideBalance));
    const masked = '••••••';
    String money(double v) =>
        hidden ? masked : CurrencyFormatter.format(v, currencyCode: currency);
    final balance = summary.balance;
    final periodCaption = isCurrent ? 'This month' : month.label;

    // Earlier months' leftover sits beside the income it adds to (or the
    // spending a shortfall adds to), so the pills still add up to the
    // balance.
    final carried = summary.carriedForward;
    String carriedCaption(double amount) => hidden
        ? 'Includes carry-over'
        : '+ ${CurrencyFormatter.formatCompact(amount, currencyCode: currency)} carried over';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const _MonthSwitcher(),
            const Spacer(),
            IconButton(
              tooltip: hidden ? 'Show amounts' : 'Hide amounts',
              icon: Icon(
                hidden ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                color: scheme.onSurfaceVariant,
              ),
              onPressed: () =>
                  ref.read(settingsProvider.notifier).setHideBalance(!hidden),
            ),
          ],
        ),
        if (!isCurrent)
          GestureDetector(
            onTap: ref.read(dashboardMonthOverrideProvider.notifier).showCurrent,
            child: Padding(
              padding: const EdgeInsets.only(left: AppSpacing.sm, top: 2),
              child: Text(
                'Tap to go back to this month',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          // A past month shows where the balance stood when it ended.
          (isCurrent ? 'Available balance' : 'Balance at month end')
              .toUpperCase(),
          style: theme.textTheme.labelMedium?.copyWith(
            color: scheme.onSurfaceVariant,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.1,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.92, end: 1),
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeOutCubic,
          builder: (context, value, child) => Opacity(
            opacity: value.clamp(0.0, 1.0),
            child: Transform.translate(
              offset: Offset(0, (1 - value) * 10),
              child: child,
            ),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              hidden
                  ? masked
                  : CurrencyFormatter.format(
                      balance,
                      currencyCode: currency,
                      spacedSymbol: true,
                    ),
              maxLines: 1,
              style: theme.textTheme.displaySmall?.copyWith(
                color: balance < 0 ? AppColors.expense : scheme.onSurface,
                fontWeight: FontWeight.w800,
                fontSize: (theme.textTheme.displaySmall?.fontSize ?? 36) + 6,
                letterSpacing: -1.4,
                height: 1.1,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _StatusPill(positive: balance >= 0),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  hidden
                      ? 'Hidden. Tap the eye to show amounts.'
                      : CurrencyFormatter.supportsWords(currency)
                      ? CurrencyFormatter.inWords(balance)
                      : (balance >= 0
                            ? 'Available to spend'
                            : 'Spent more than you had'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xl),
        Row(
          children: [
            Expanded(
              child: _MoneyPill(
                label: 'Expenses',
                value: money(summary.totalExpense),
                caption: carried < 0 ? carriedCaption(-carried) : periodCaption,
                icon: Icons.north_east_rounded,
                color: AppColors.coral,
                onTap: () =>
                    _openFiltered(context, ref, TransactionType.expense),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: _MoneyPill(
                label: 'Income',
                value: money(summary.totalIncome),
                caption: carried > 0 ? carriedCaption(carried) : periodCaption,
                icon: Icons.south_west_rounded,
                color: AppColors.income,
                onTap: () => _openFiltered(context, ref, TransactionType.income),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// "Saved" while the balance is up, "Over" once it goes below zero.
class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.positive});

  final bool positive;

  @override
  Widget build(BuildContext context) {
    final color = positive ? AppColors.income : AppColors.expense;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            positive ? Icons.trending_up_rounded : Icons.trending_down_rounded,
            size: 14,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            positive ? 'Saved' : 'Over',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

/// Expenses or income for the month: a tinted pill with a solid icon dot.
/// Tapping it opens Activity filtered to that type.
class _MoneyPill extends StatelessWidget {
  const _MoneyPill({
    required this.label,
    required this.value,
    required this.caption,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String label;
  final String value;
  final String caption;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final tint = Color.alphaBlend(
      color.withValues(alpha: dark ? 0.18 : 0.10),
      scheme.surfaceContainerLowest,
    );
    final labelColor = dark
        ? Color.lerp(color, Colors.white, 0.35)!
        : Color.lerp(color, Colors.black, 0.22)!;
    final radius = BorderRadius.circular(AppRadii.card);

    return Material(
      color: tint,
      borderRadius: radius,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
          child: Row(
            children: [
              Container(
                width: 36.rr,
                height: 36.rr,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                child: Icon(icon, size: 18.rr, color: Colors.white),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: labelColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        value,
                        maxLines: 1,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    Text(
                      caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// ‹ November 2026 › as a light pill. Steps back through past months;
/// never forward past the current one.
class _MonthSwitcher extends ConsumerWidget {
  const _MonthSwitcher();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(dashboardMonthProvider);
    final isCurrent = ref.watch(isDashboardOnCurrentMonthProvider);
    final months = ref.read(dashboardMonthOverrideProvider.notifier);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: _Panel.tintOf(context),
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Previous month',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.chevron_left_rounded),
            onPressed: months.previous,
          ),
          GestureDetector(
            onTap: isCurrent ? null : months.showCurrent,
            child: Text(
              month.label,
              key: const Key('dashboard-month'),
              style: theme.textTheme.titleSmall,
            ),
          ),
          IconButton(
            tooltip: 'Next month',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.chevron_right_rounded),
            color: scheme.onSurface,
            onPressed: isCurrent ? null : months.next,
          ),
        ],
      ),
    );
  }
}

/// Spending on each of the last seven days as rounded bars, today (or the
/// month's last day, for a past month) picked out in the accent colour.
/// Tapping a bar shows its amount.
class _WeekSpending extends ConsumerStatefulWidget {
  const _WeekSpending({required this.currency});

  final String currency;

  @override
  ConsumerState<_WeekSpending> createState() => _WeekSpendingState();
}

class _WeekSpendingState extends ConsumerState<_WeekSpending> {
  int? _selected;

  static const _maxBar = 84.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final month = ref.watch(dashboardMonthProvider);
    final isCurrent = ref.watch(isDashboardOnCurrentMonthProvider);
    final hidden = ref.watch(settingsProvider.select((s) => s.hideBalance));
    final txs =
        ref.watch(allTransactionsStreamProvider).asData?.value ?? const [];
    final days = lastSevenDaysSpending(
      txs,
      lastDay: isCurrent ? DateTime.now() : month.end,
    );
    final total = days.fold<double>(0, (s, d) => s + d.amount);
    final most = days.fold<double>(0, (m, d) => d.amount > m ? d.amount : m);
    final selected = _selected ?? days.length - 1;
    String compact(double v) => hidden
        ? '••••'
        : CurrencyFormatter.formatCompact(v, currencyCode: widget.currency);

    // Title inside the panel keeps the chart compact, so on most phones it
    // sits clear of the Add button below it.
    return _Panel(
      key: const Key('week-chart'),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  isCurrent ? 'Last 7 days' : 'Last 7 days of ${month.label}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                '${compact(total)} spent',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            height: _maxBar + 52,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < days.length; i++)
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => setState(() => _selected = i),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          AnimatedOpacity(
                            opacity: i == selected ? 1 : 0,
                            duration: const Duration(milliseconds: 180),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                compact(days[i].amount),
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: scheme.primary,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 350),
                            curve: Curves.easeOutCubic,
                            width: 24.rw,
                            height: most <= 0
                                ? 8
                                : (days[i].amount / most * _maxBar).clamp(
                                    8.0,
                                    _maxBar,
                                  ),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(
                                AppRadii.pill,
                              ),
                              color: i == selected
                                  ? null
                                  : scheme.primary.withValues(alpha: 0.14),
                              gradient: i == selected
                                  ? const LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [
                                        Color(0xFF2BB3B5),
                                        AppColors.primary,
                                      ],
                                    )
                                  : null,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            DateFormat('EEE').format(days[i].day),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: i == selected
                                  ? scheme.onSurface
                                  : scheme.onSurfaceVariant,
                              fontWeight: i == selected
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                            ),
                          ),
                        ],
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

/// The month's spending by category, as a list with progress bars.
class _WhereItWent extends ConsumerWidget {
  final DashboardSummary summary;
  final String currency;

  const _WhereItWent({required this.summary, required this.currency});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (summary.expenseByCategory.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpacing.xxl),
        SectionHeader(
          title: 'Where your money went',
          actionLabel: 'Reports',
          onAction: () => context.go('/reports'),
        ),
        const SizedBox(height: AppSpacing.md),
        _Panel(
          child: _ExpenseBreakdown(
            data: summary.expenseByCategory,
            currency: currency,
          ),
        ),
      ],
    );
  }
}

/// Each account and its balance, once the user has added one.
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

/// The month's spending by category: one row per category the user spent
/// in, with its icon, amount, share and a progress bar in its own colour.
class _ExpenseBreakdown extends ConsumerStatefulWidget {
  final Map<String, double> data;
  final String currency;

  const _ExpenseBreakdown({required this.data, required this.currency});

  /// Rows shown before "Show all".
  static const collapsedRows = 6;

  /// For a category whose name no longer matches one of the user's (it was
  /// renamed since): neutral, so it never borrows another category's colour.
  static const _unmatched = Color(0xFF94A3B8);

  @override
  ConsumerState<_ExpenseBreakdown> createState() => _ExpenseBreakdownState();
}

class _ExpenseBreakdownState extends ConsumerState<_ExpenseBreakdown> {
  bool _showAll = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final currency = widget.currency;
    final hidden = ref.watch(settingsProvider.select((s) => s.hideBalance));

    final total = widget.data.values.fold<double>(0, (sum, v) => sum + v);
    if (total <= 0) {
      return const EmptyState(
        icon: Icons.pie_chart_outline_rounded,
        title: 'No spending yet',
        message: 'Expenses you log this month will break down here.',
      );
    }

    // Entries carry their category's name; match it back to the user's own
    // expense categories for the colour and icon.
    final byName = <String, CategoryModel>{
      for (final c in ref.watch(categoryLookupProvider).values)
        if (c.type == TransactionType.expense) c.name.toLowerCase(): c,
    };
    CategoryModel? categoryOf(String name) => byName[name.toLowerCase()];

    final slices = buildExpenseSlices(
      widget.data,
      colorOf: (name, _) {
        final c = categoryOf(name);
        return c == null ? _ExpenseBreakdown._unmatched : categoryColor(c.color);
      },
    );
    final collapsible = slices.length > _ExpenseBreakdown.collapsedRows;
    final rows = collapsible && !_showAll
        ? slices.take(_ExpenseBreakdown.collapsedRows).toList()
        : slices;

    return Column(
      children: [
        for (final slice in rows)
          // Each category opens Reports, where a category lists its
          // entries.
          InkWell(
            key: Key('breakdown-${slice.label}'),
            onTap: () => context.go('/reports'),
            borderRadius: BorderRadius.circular(AppRadii.control),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(
                children: [
                  IconTile(
                    icon: categoryOf(slice.label) == null
                        ? Icons.category_rounded
                        : iconFor(categoryOf(slice.label)!.icon),
                    color: slice.color,
                    size: 38.rr,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                slice.label,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            Text(
                              hidden
                                  ? '••••'
                                  : CurrencyFormatter.formatCompact(
                                      slice.amount,
                                      currencyCode: currency,
                                    ),
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: slice.amount / total,
                                  minHeight: 6,
                                  color: slice.color,
                                  backgroundColor:
                                      slice.color.withValues(alpha: 0.14),
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 44.rw,
                              child: Text(
                                '${(slice.amount / total * 100).toStringAsFixed(0)}%',
                                textAlign: TextAlign.right,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (collapsible)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const Key('breakdown-toggle'),
              onPressed: () => setState(() => _showAll = !_showAll),
              icon: Icon(
                _showAll
                    ? Icons.expand_less_rounded
                    : Icons.expand_more_rounded,
              ),
              label: Text(
                _showAll
                    ? 'Show fewer'
                    : 'Show all ${slices.length} categories',
              ),
            ),
          ),
      ],
    );
  }
}

/// The balance and the Expenses / Income pills while there is nothing to
/// show yet, drawn in their shape so the screen reads as "loading", not
/// "empty".
class DashboardSummarySkeleton extends StatelessWidget {
  const DashboardSummarySkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(
      key: Key('dashboard-summary-skeleton'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SkeletonBox(width: 190, height: 40, radius: 20),
        SizedBox(height: AppSpacing.lg),
        SkeletonBox(width: 130, height: 12, radius: 6),
        SizedBox(height: AppSpacing.sm),
        SkeletonBox(width: 230, height: 44, radius: 12),
        SizedBox(height: AppSpacing.md),
        SkeletonBox(width: 200, height: 12, radius: 6),
        SizedBox(height: AppSpacing.xl),
        Row(
          children: [
            Expanded(child: SkeletonBox(height: 72, radius: AppRadii.card)),
            SizedBox(width: AppSpacing.md),
            Expanded(child: SkeletonBox(height: 72, radius: AppRadii.card)),
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
