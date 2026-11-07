import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import '../../widgets/summary_card.dart';
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
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab-dashboard',
        onPressed: () => showAddTransactionSheet(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add'),
      ),
      // White status-bar icons over the coloured header.
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: RefreshIndicator(
          color: Theme.of(context).colorScheme.primary,
          onRefresh: () => ref.read(syncManagerProvider).syncNow(),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              // The header and the cards that ride over its lower edge share
              // one box: a scroll view paints its first sliver on top, so
              // cards in the next sliver would slide under the header.
              SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _DashboardHeader(
                      greeting: greetingFor(DateTime.now()),
                      name: displayGreetingName,
                      avatar: _ProfileButton(
                        photoUrl: photoUrl,
                        name: name,
                        email: user?.email,
                      ),
                      child: ledger == _Ledger.ready
                          ? _BalanceHeader(
                              summary: summary,
                              currency: settings.currency,
                            )
                          : const _HeaderSkeleton(),
                    ),
                    Transform.translate(
                      offset: const Offset(0, -_DashboardHeader.overlap),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.gutter,
                        ),
                        child: switch (ledger) {
                          _Ledger.ready => _SummaryCards(
                            summary: summary,
                            currency: settings.currency,
                          ),
                          _Ledger.loading => const DashboardSummarySkeleton(),
                          _Ledger.failed => AppErrorState(
                            message: "We couldn't open your local ledger.",
                            onRetry: () =>
                                ref.invalidate(localStoreReadyProvider),
                          ),
                        },
                      ),
                    ),
                  ],
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.gutter,
                  // The cards above were pulled up by the overlap, which
                  // leaves that much room below them already.
                  0,
                  AppSpacing.gutter,
                  AppSpacing.scrollBottom,
                ),
                sliver: SliverToBoxAdapter(
                  child: Transform.translate(
                    offset: const Offset(0, -_DashboardHeader.overlap / 2),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (ledger == _Ledger.ready)
                          _SummaryBody(
                            summary: summary,
                            currency: settings.currency,
                          ),
                        const _AccountsSection(),
                        const _CreditCardSection(),
                        const SizedBox(height: AppSpacing.xxl),
                        SectionHeader(
                          title: "Today's activity",
                          subtitle: DateFormat(
                            'EEEE, MMM d',
                          ).format(DateTime.now()),
                          actionLabel: 'See all',
                          onAction: () => context.go('/transactions'),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        if (awaitingCloud)
                          const _ListSkeleton()
                        else
                          recentAsync.when(
                            data: (txs) {
                              final recent = todaysActivity(
                                txs,
                                now: DateTime.now(),
                              );

                              if (recent.isEmpty) {
                                // An empty day and an empty ledger need
                                // different copy: telling someone with months
                                // of history that they have "no transactions
                                // yet" would be wrong.
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
                                    onAction: () =>
                                        showAddTransactionSheet(context),
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
                                        category:
                                            categories[recent[i].categoryId],
                                        creditCard:
                                            cards[recent[i].creditCardId],
                                        // Every row is from today, so the
                                        // date would repeat on each one; the
                                        // time is enough.
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
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.outlineVariant,
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
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Where the local ledger stands, for the dashboard's loading states.
enum _Ledger { loading, ready, failed }

/// The coloured top of the dashboard: who is signed in, the month, and the
/// balance, on the hero gradient with a rounded lower edge.
class _DashboardHeader extends StatelessWidget {
  const _DashboardHeader({
    required this.greeting,
    required this.name,
    required this.avatar,
    required this.child,
  });

  /// How far the summary cards ride up over the header's lower edge.
  static const overlap = 34.0;

  final String greeting;
  final String name;
  final Widget avatar;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    const radius = BorderRadius.vertical(bottom: Radius.circular(34));

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: dark ? AppColors.heroGradientDark : AppColors.heroGradient,
        borderRadius: radius,
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(
          children: [
            // Soft rings for depth; purely decorative.
            const Positioned(
              top: -70,
              right: -50,
              child: _HeaderRing(size: 210, alpha: 0.10),
            ),
            const Positioned(
              bottom: -60,
              left: -80,
              child: _HeaderRing(size: 190, alpha: 0.07),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.gutter + 2,
                MediaQuery.paddingOf(context).top + AppSpacing.md,
                AppSpacing.gutter + 2,
                overlap + AppSpacing.xl,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      avatar,
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              greeting,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: Colors.white.withValues(alpha: 0.8),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            // Scale down rather than ellipsize: a long name
                            // should stay fully readable.
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                name,
                                maxLines: 1,
                                softWrap: false,
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  child,
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderRing extends StatelessWidget {
  const _HeaderRing({required this.size, required this.alpha});

  final double size;
  final double alpha;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white.withValues(alpha: alpha),
          width: 28,
        ),
      ),
    ),
  );
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
    return Tooltip(
      message: 'Profile & settings',
      child: Material(
        color: Colors.white.withValues(alpha: 0.18),
        shape: CircleBorder(
          side: BorderSide(
            color: Colors.white.withValues(alpha: 0.6),
            width: 1.5,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push('/settings'),
          child: Padding(
            padding: const EdgeInsets.all(3),
            child: UserAvatar(
              radius: 21,
              photoUrl: photoUrl,
              name: name,
              email: email,
              backgroundColor: Colors.white,
              foregroundColor: AppColors.primary,
              textStyle: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 15,
                color: AppColors.primary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The month switcher and the balance, centred on the header.
class _BalanceHeader extends ConsumerWidget {
  final DashboardSummary summary;
  final String currency;

  const _BalanceHeader({required this.summary, required this.currency});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isCurrent = ref.watch(isDashboardOnCurrentMonthProvider);
    final hidden = ref.watch(settingsProvider.select((s) => s.hideBalance));
    final balance = summary.balance;
    const onHero = Colors.white;

    return Column(
      children: [
        const _MonthBar(),
        const SizedBox(height: AppSpacing.xl),
        Text(
          // A past month shows where the balance stood when it ended.
          (isCurrent ? 'Available balance' : 'Balance at month end')
              .toUpperCase(),
          textAlign: TextAlign.center,
          style: theme.textTheme.labelMedium?.copyWith(
            color: onHero.withValues(alpha: 0.8),
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.92, end: 1),
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeOutCubic,
          builder: (context, value, child) => Opacity(
            opacity: value.clamp(0.0, 1.0),
            child: Transform.translate(
              offset: Offset(0, (1 - value) * 12),
              child: child,
            ),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              hidden
                  ? '••••••'
                  : CurrencyFormatter.format(
                      balance,
                      currencyCode: currency,
                      spacedSymbol: true,
                    ),
              maxLines: 1,
              style: theme.textTheme.displaySmall?.copyWith(
                color: onHero,
                fontWeight: FontWeight.w800,
                fontSize: (theme.textTheme.displaySmall?.fontSize ?? 36) + 6,
                letterSpacing: -1.4,
                height: 1.05,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          hidden
              ? 'Hidden. Tap the eye to show amounts.'
              : CurrencyFormatter.supportsWords(currency)
              ? CurrencyFormatter.inWords(balance)
              : (balance >= 0
                    ? 'Available to spend'
                    : 'Spent more than you had'),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            color: onHero.withValues(alpha: 0.82),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _StatusPill(positive: balance >= 0),
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
    final color = positive ? Colors.white : AppColors.expense;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 6),
      decoration: BoxDecoration(
        color: positive
            ? Colors.white.withValues(alpha: 0.18)
            : const Color(0xFFFFE4E8),
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            positive ? Icons.trending_up_rounded : Icons.trending_down_rounded,
            size: 15,
            color: color,
          ),
          const SizedBox(width: 5),
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

/// The header's placeholder while the ledger loads: soft white bars in the
/// shape of the month switcher and balance, pulsing gently.
class _HeaderSkeleton extends StatefulWidget {
  const _HeaderSkeleton();

  @override
  State<_HeaderSkeleton> createState() => _HeaderSkeletonState();
}

class _HeaderSkeletonState extends State<_HeaderSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) {
        final alpha = 0.14 + 0.14 * _pulse.value;
        Widget bar(double width, double height) => Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: alpha),
            borderRadius: BorderRadius.circular(height / 2),
          ),
        );
        return Column(
          key: const Key('dashboard-header-skeleton'),
          children: [
            bar(double.infinity, 48),
            const SizedBox(height: AppSpacing.xl),
            bar(140, 12),
            const SizedBox(height: AppSpacing.md),
            bar(230, 42),
            const SizedBox(height: AppSpacing.md),
            bar(190, 12),
            const SizedBox(height: AppSpacing.md),
            bar(84, 28),
          ],
        );
      },
    );
  }
}

/// The month's income and expense cards. Each opens Activity filtered to it.
class _SummaryCards extends ConsumerWidget {
  final DashboardSummary summary;
  final String currency;

  const _SummaryCards({required this.summary, required this.currency});

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
    String money(double v) =>
        hidden ? masked : CurrencyFormatter.format(v, currencyCode: currency);
    final periodCaption = isCurrent ? 'This month' : month.label;

    // Earlier months' leftover sits beside the income it adds to (or the
    // spending a shortfall adds to), so the cards still add up to the balance.
    final carried = summary.carriedForward;
    String carriedCaption(double amount) => hidden
        ? 'Includes carry-over'
        : '+ ${CurrencyFormatter.formatCompact(amount, currencyCode: currency)} carried over';

    return Row(
      children: [
        Expanded(
          child: SummaryCard(
            label: 'Income',
            value: money(summary.totalIncome),
            caption: carried > 0 ? carriedCaption(carried) : periodCaption,
            icon: Icons.south_west_rounded,
            color: AppColors.income,
            onTap: () => _openFiltered(context, ref, TransactionType.income),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: SummaryCard(
            label: 'Expenses',
            value: money(summary.totalExpense),
            caption: carried < 0 ? carriedCaption(-carried) : periodCaption,
            icon: Icons.north_east_rounded,
            color: AppColors.coral,
            onTap: () =>
                _openFiltered(context, ref, TransactionType.expense),
          ),
        ),
      ],
    );
  }
}

/// The insight strip and the category chart, once there is spending.
class _SummaryBody extends ConsumerWidget {
  final DashboardSummary summary;
  final String currency;

  const _SummaryBody({required this.summary, required this.currency});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(dashboardMonthProvider);
    final isCurrent = ref.watch(isDashboardOnCurrentMonthProvider);
    if (summary.expenseByCategory.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _InsightStrip(
          data: summary.expenseByCategory,
          when: isCurrent ? 'this month' : 'in ${month.label}',
        ),
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
    );
  }
}

/// One friendly line about the month, on a dark pill: which category took
/// the biggest share. Tapping it opens Reports.
class _InsightStrip extends StatelessWidget {
  const _InsightStrip({required this.data, required this.when});

  final Map<String, double> data;

  /// "this month" or "in October 2026".
  final String when;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final total = data.values.fold<double>(0, (a, b) => a + b);
    final top = data.entries.reduce((a, b) => a.value >= b.value ? a : b);
    final share = total <= 0 ? 0 : (top.value / total * 100).round();
    final text = share >= 100
        ? 'All of your spending $when went on ${top.key}'
        : '${top.key} made up $share% of your spending $when';

    return Material(
      key: const Key('dashboard-insight'),
      color: dark ? theme.colorScheme.surfaceContainerHigh : AppColors.ink,
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.go('/reports'),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 16, 10),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [AppColors.coral, AppColors.pink],
                  ),
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  size: 17,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: Colors.white.withValues(alpha: 0.7),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// ‹ November 2026 › with the hide-amounts eye, as a frosted pill on the
/// header. Steps back through past months; never forward past the current
/// one.
class _MonthBar extends ConsumerWidget {
  const _MonthBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(dashboardMonthProvider);
    final isCurrent = ref.watch(isDashboardOnCurrentMonthProvider);
    final hidden = ref.watch(settingsProvider.select((s) => s.hideBalance));
    final months = ref.read(dashboardMonthOverrideProvider.notifier);
    final theme = Theme.of(context);
    final onHero = IconButton.styleFrom(
      foregroundColor: Colors.white,
      disabledForegroundColor: Colors.white.withValues(alpha: 0.35),
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Previous month',
            visualDensity: VisualDensity.compact,
            style: onHero,
            icon: const Icon(Icons.chevron_left_rounded),
            onPressed: months.previous,
          ),
          Expanded(
            child: GestureDetector(
              onTap: isCurrent ? null : months.showCurrent,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    month.label,
                    key: const Key('dashboard-month'),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: Colors.white,
                    ),
                  ),
                  if (!isCurrent)
                    Text(
                      'Tap to go back to this month',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                    ),
                ],
              ),
            ),
          ),
          IconButton(
            tooltip: 'Next month',
            visualDensity: VisualDensity.compact,
            style: onHero,
            icon: const Icon(Icons.chevron_right_rounded),
            onPressed: isCurrent ? null : months.next,
          ),
          IconButton(
            tooltip: hidden ? 'Show amounts' : 'Hide amounts',
            visualDensity: VisualDensity.compact,
            style: onHero,
            icon: Icon(
              hidden ? Icons.visibility_off_rounded : Icons.visibility_rounded,
            ),
            onPressed: () =>
                ref.read(settingsProvider.notifier).setHideBalance(!hidden),
          ),
        ],
      ),
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

/// Donut + legend of the month's spending by category. The legend carries
/// each category's icon, amount and share, so the chart never has to be
/// decoded from colour alone.
class _ExpenseBreakdown extends ConsumerStatefulWidget {
  final Map<String, double> data;
  final String currency;

  const _ExpenseBreakdown({required this.data, required this.currency});

  /// Legend rows shown before "Show all".
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
                        radius: 26.rr,
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
        for (final slice in rows)
          Padding(
            key: Key('breakdown-${slice.label}'),
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Row(
              children: [
                IconTile(
                  icon: categoryOf(slice.label) == null
                      ? Icons.category_rounded
                      : iconFor(categoryOf(slice.label)!.icon),
                  color: slice.color,
                  size: 34.rr,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    slice.label,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
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
                    fontWeight: FontWeight.w800,
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

/// The income / expense cards while there is nothing to show yet, drawn in
/// the shape of the real ones so the screen reads as "loading", not
/// "empty". The header above shimmers its own balance placeholder.
class DashboardSummarySkeleton extends StatelessWidget {
  const DashboardSummarySkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      key: const Key('dashboard-summary-skeleton'),
      children: [
        for (final i in [0, 1]) ...[
          if (i == 1) const SizedBox(width: AppSpacing.md),
          const Expanded(
            child: AppCard(
              // Income / expense: icon, label, amount.
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBox(width: 38, height: 38, radius: 19),
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
