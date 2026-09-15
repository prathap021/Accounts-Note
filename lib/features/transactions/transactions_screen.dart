import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/currency_formatter.dart';
import '../../data/repositories/transaction_repository.dart';
import '../../models/transaction_model.dart';
import '../../providers/category_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/transaction_provider.dart';
import '../../widgets/add_transaction_sheet.dart';
import '../../widgets/sync_status_chip.dart';
import '../../widgets/transaction_tile.dart';

/// One calendar day of transactions plus that day's net movement.
class _DayGroup {
  final DateTime day;
  final List<TransactionModel> items;

  _DayGroup(this.day, this.items);

  double get income => items
      .where((t) => t.type == TransactionType.income)
      .fold<double>(0, (sum, t) => sum + t.amount);

  double get expense => items
      .where((t) => t.type == TransactionType.expense)
      .fold<double>(0, (sum, t) => sum + t.amount);
}

class TransactionsScreen extends ConsumerStatefulWidget {
  const TransactionsScreen({super.key});

  @override
  ConsumerState<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends ConsumerState<TransactionsScreen> {
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // The filter can be set from elsewhere (e.g. tapping Income on the
    // dashboard), so seed the box from whatever is already applied.
    _searchController.text = ref.read(transactionFilterProvider).searchQuery ?? '';
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _setFilter(TransactionFilter filter) =>
      ref.read(transactionFilterProvider.notifier).update(filter);

  void _setSearch(String? value) {
    final f = ref.read(transactionFilterProvider);
    _setFilter(TransactionFilter(
      startDate: f.startDate,
      endDate: f.endDate,
      type: f.type,
      categoryId: f.categoryId,
      paymentMethod: f.paymentMethod,
      searchQuery: value,
    ));
  }

  void _clearAll() {
    _searchController.clear();
    _setFilter(const TransactionFilter());
  }

  List<_DayGroup> _group(List<TransactionModel> txs) {
    final groups = <DateTime, List<TransactionModel>>{};
    for (final tx in txs) {
      final day = DateTime(tx.date.year, tx.date.month, tx.date.day);
      groups.putIfAbsent(day, () => []).add(tx);
    }
    final keys = groups.keys.toList()..sort((a, b) => b.compareTo(a));
    return [for (final key in keys) _DayGroup(key, groups[key]!)];
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final txsAsync = ref.watch(transactionsStreamProvider);
    final filter = ref.watch(transactionFilterProvider);
    final hasFilters = !filter.isEmpty;

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab-activity',
        onPressed: () => showAddTransactionSheet(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add'),
      ),
      body: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          AppSliverHeader(
            title: 'Activity',
            eyebrow: 'Your ledger',
            actions: [
              const Padding(
                padding: EdgeInsets.only(right: AppSpacing.sm),
                child: Center(child: SyncStatusChip()),
              ),
              _FilterButton(active: hasFilters, onTap: _showFilterSheet),
            ],
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.gutter,
              0,
              AppSpacing.gutter,
              AppSpacing.md,
            ),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SyncFailureBanner(),
                  TextField(
                    controller: _searchController,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: 'Search notes or categories',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: (filter.searchQuery?.isNotEmpty ?? false)
                          ? IconButton(
                              tooltip: 'Clear search',
                              icon: const Icon(Icons.clear_rounded),
                              onPressed: () {
                                _searchController.clear();
                                _setSearch(null);
                                FocusScope.of(context).unfocus();
                              },
                            )
                          : null,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg,
                        vertical: 14,
                      ),
                    ),
                    onChanged: _setSearch,
                  ),
                  if (hasFilters) ...[
                    const SizedBox(height: AppSpacing.md),
                    _ActiveFilterChips(
                      filter: filter,
                      onChanged: _setFilter,
                      onClearAll: _clearAll,
                      onClearSearch: () {
                        _searchController.clear();
                        _setSearch(null);
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),
          txsAsync.when(
            data: (txs) {
              if (txs.isEmpty) {
                return SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: hasFilters
                      ? EmptyState(
                          icon: Icons.filter_alt_off_outlined,
                          title: 'No matches',
                          message:
                              'No transactions fit the filters you have applied.',
                          actionLabel: 'Clear filters',
                          onAction: _clearAll,
                        )
                      : EmptyState(
                          icon: Icons.receipt_long_outlined,
                          title: 'Nothing logged yet',
                          message:
                              'Add your first income or expense to start your ledger.',
                          actionLabel: 'Add transaction',
                          onAction: () => showAddTransactionSheet(context),
                        ),
                  ),
                );
              }

              final groups = _group(txs);
              return SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.gutter,
                  0,
                  AppSpacing.gutter,
                  AppSpacing.scrollBottom,
                ),
                sliver: SliverList.builder(
                  itemCount: groups.length,
                  itemBuilder: (context, i) => Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xl),
                    child: _DaySection(
                      group: groups[i],
                      currency: settings.currency,
                    ),
                  ),
                ),
              );
            },
            loading: () => const SliverToBoxAdapter(
              child: Padding(
                padding: AppSpacing.screenPadding,
                child: _ActivitySkeleton(),
              ),
            ),
            error: (e, _) => SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: AppSpacing.screenPadding,
                child: Center(
                  child: AppErrorState(
                    message: "We couldn't load your transactions.",
                    onRetry: () => ref.invalidate(transactionsStreamProvider),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showFilterSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _FilterSheet(
        current: ref.read(transactionFilterProvider),
        onApply: (filter) {
          _setFilter(filter);
          Navigator.pop(ctx);
        },
      ),
    );
  }
}

class _FilterButton extends StatelessWidget {
  final bool active;
  final VoidCallback onTap;

  const _FilterButton({required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Badge(
      isLabelVisible: active,
      backgroundColor: Theme.of(context).colorScheme.primary,
      smallSize: 9,
      offset: const Offset(-10, 4),
      child: HeaderAction(
        icon: Icons.tune_rounded,
        tooltip: active ? 'Filters applied' : 'Filter activity',
        highlighted: active,
        onTap: onTap,
      ),
    );
  }
}

/// Filters are invisible state that silently changes what the list means, so
/// each one is shown as a chip the user can remove in place.
class _ActiveFilterChips extends ConsumerWidget {
  final TransactionFilter filter;
  final ValueChanged<TransactionFilter> onChanged;
  final VoidCallback onClearAll;
  final VoidCallback onClearSearch;

  const _ActiveFilterChips({
    required this.filter,
    required this.onChanged,
    required this.onClearAll,
    required this.onClearSearch,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories =
        ref.watch(categoriesStreamProvider(filter.type)).asData?.value ?? [];
    final categoryName = filter.categoryId == null
        ? null
        : categories
            .where((c) => c.id == filter.categoryId)
            .map((c) => c.name)
            .firstOrNull;

    TransactionFilter without({
      bool type = false,
      bool category = false,
      bool dates = false,
    }) {
      return TransactionFilter(
        startDate: dates ? null : filter.startDate,
        endDate: dates ? null : filter.endDate,
        type: type ? null : filter.type,
        categoryId: category ? null : filter.categoryId,
        paymentMethod: filter.paymentMethod,
        searchQuery: filter.searchQuery,
      );
    }

    final dateFormat = DateFormat('MMM d');

    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (filter.type != null)
          _RemovableChip(
            label: filter.type == TransactionType.income ? 'Income' : 'Expense',
            icon: filter.type == TransactionType.income
                ? Icons.south_west_rounded
                : Icons.north_east_rounded,
            onRemove: () => onChanged(without(type: true, category: true)),
          ),
        if (filter.categoryId != null)
          _RemovableChip(
            label: categoryName ?? 'Category',
            icon: Icons.sell_outlined,
            onRemove: () => onChanged(without(category: true)),
          ),
        if (filter.startDate != null && filter.endDate != null)
          _RemovableChip(
            label:
                '${dateFormat.format(filter.startDate!)} – ${dateFormat.format(filter.endDate!)}',
            icon: Icons.date_range_rounded,
            onRemove: () => onChanged(without(dates: true)),
          ),
        if (filter.searchQuery?.isNotEmpty ?? false)
          _RemovableChip(
            label: '"${filter.searchQuery}"',
            icon: Icons.search_rounded,
            onRemove: onClearSearch,
          ),
        TextButton(
          onPressed: onClearAll,
          style: TextButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          ),
          child: const Text('Clear all'),
        ),
      ],
    );
  }
}

class _RemovableChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onRemove;

  const _RemovableChip({
    required this.label,
    required this.icon,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return InputChip(
      avatar: Icon(icon, size: 16, color: scheme.primary),
      label: Text(label),
      onDeleted: onRemove,
      deleteIcon: const Icon(Icons.close_rounded, size: 16),
      backgroundColor: scheme.primary.withValues(alpha: 0.1),
      side: BorderSide(color: scheme.primary.withValues(alpha: 0.28)),
      labelStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: scheme.primary,
            fontWeight: FontWeight.w700,
          ),
      deleteIconColor: scheme.primary,
      visualDensity: VisualDensity.compact,
    );
  }
}

/// One side of a day's totals — money in, or money out.
class _DayTotal extends StatelessWidget {
  final double amount;
  final bool isIncome;
  final String currency;

  const _DayTotal({
    required this.amount,
    required this.isIncome,
    required this.currency,
  });

  @override
  Widget build(BuildContext context) {
    final color = isIncome ? AppColors.income : AppColors.expense;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          isIncome ? Icons.south_west_rounded : Icons.north_east_rounded,
          size: 13,
          color: color,
        ),
        const SizedBox(width: 3),
        Text(
          CurrencyFormatter.format(amount, currencyCode: currency),
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: color,
              ),
        ),
      ],
    );
  }
}

class _DaySection extends ConsumerWidget {
  final _DayGroup group;
  final String currency;

  const _DaySection({required this.group, required this.currency});

  String _dayLabel() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final diff = today.difference(group.day).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    if (group.day.year == now.year) {
      return DateFormat('EEEE, MMM d').format(group.day);
    }
    return DateFormat('MMM d, yyyy').format(group.day);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final categories = ref.watch(categoryLookupProvider);
    final income = group.income;
    final expense = group.expense;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(
            left: AppSpacing.xs,
            right: AppSpacing.xs,
            bottom: AppSpacing.sm,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _dayLabel(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              // Money in and money out for the day, kept separate rather than
              // collapsed into one net figure. Scales down so two large
              // amounts never overflow the row.
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (income > 0)
                        _DayTotal(
                          amount: income,
                          isIncome: true,
                          currency: currency,
                        ),
                      if (income > 0 && expense > 0)
                        const SizedBox(width: AppSpacing.md),
                      if (expense > 0)
                        _DayTotal(
                          amount: expense,
                          isIncome: false,
                          currency: currency,
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        AppCard(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.sm,
          ),
          child: Column(
            children: [
              for (var i = 0; i < group.items.length; i++) ...[
                TransactionTile(
                  currency: currency,
                  transaction: group.items[i],
                  category: categories[group.items[i].categoryId],
                  showDate: false,
                  onTap: () => context.push(
                    '/transaction/edit',
                    extra: group.items[i],
                  ),
                  onDelete: () => ref
                      .read(transactionActionsProvider.notifier)
                      .deleteTransaction(group.items[i].id),
                ),
                if (i != group.items.length - 1)
                  Divider(
                    height: 1,
                    indent: AppSpacing.sm,
                    endIndent: AppSpacing.sm,
                    color: scheme.outlineVariant,
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _ActivitySkeleton extends StatelessWidget {
  const _ActivitySkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SkeletonBox(height: 64, radius: AppRadii.card),
        const SizedBox(height: AppSpacing.xl),
        for (var group = 0; group < 2; group++) ...[
          const SkeletonBox(width: 120, height: 12, radius: 6),
          const SizedBox(height: AppSpacing.md),
          const SkeletonBox(height: 148, radius: AppRadii.card),
          const SizedBox(height: AppSpacing.xl),
        ],
      ],
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

class _FilterSheet extends ConsumerStatefulWidget {
  final TransactionFilter current;
  final ValueChanged<TransactionFilter> onApply;
  const _FilterSheet({required this.current, required this.onApply});

  @override
  ConsumerState<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends ConsumerState<_FilterSheet> {
  TransactionType? _type;
  String? _categoryId;
  DateTimeRange? _range;

  @override
  void initState() {
    super.initState();
    _type = widget.current.type;
    _categoryId = widget.current.categoryId;
    if (widget.current.startDate != null && widget.current.endDate != null) {
      _range = DateTimeRange(
        start: widget.current.startDate!,
        end: widget.current.endDate!,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final categoriesAsync = ref.watch(categoriesStreamProvider(_type));
    final dateFormat = DateFormat('MMM d, yyyy');

    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.xl,
        right: AppSpacing.xl,
        top: AppSpacing.sm,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.xl,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Filter activity', style: theme.textTheme.titleLarge),
            const SizedBox(height: AppSpacing.xl),
            const SectionLabel('Type'),
            SegmentedButton<TransactionType?>(
              segments: const [
                ButtonSegment(value: null, label: Text('All')),
                ButtonSegment(
                  value: TransactionType.income,
                  label: Text('Income'),
                ),
                ButtonSegment(
                  value: TransactionType.expense,
                  label: Text('Expense'),
                ),
              ],
              selected: {_type},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() {
                _type = s.first;
                _categoryId = null;
              }),
            ),
            const SizedBox(height: AppSpacing.xl),
            const SectionLabel('Category'),
            categoriesAsync.when(
              data: (categories) => Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  ChoiceChip(
                    label: const Text('All'),
                    selected: _categoryId == null,
                    onSelected: (_) => setState(() => _categoryId = null),
                  ),
                  for (final c in categories)
                    ChoiceChip(
                      label: Text(c.name),
                      selected: _categoryId == c.id,
                      onSelected: (_) => setState(() => _categoryId = c.id),
                    ),
                ],
              ),
              loading: () => const LinearProgressIndicator(),
              error: (e, st) => const SizedBox.shrink(),
            ),
            const SizedBox(height: AppSpacing.xl),
            const SectionLabel('Date range'),
            AppCard(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.md,
              ),
              onTap: () async {
                final picked = await showDateRangePicker(
                  context: context,
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2100),
                  initialDateRange: _range,
                );
                if (picked != null) setState(() => _range = picked);
              },
              child: Row(
                children: [
                  Icon(Icons.date_range_rounded, color: scheme.primary, size: 20),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      _range == null
                          ? 'Any date'
                          : '${dateFormat.format(_range!.start)} – ${dateFormat.format(_range!.end)}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (_range != null)
                    IconButton(
                      tooltip: 'Clear date range',
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.close_rounded, size: 18),
                      onPressed: () => setState(() => _range = null),
                    )
                  else
                    Icon(
                      Icons.chevron_right_rounded,
                      color: scheme.onSurfaceVariant,
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => widget.onApply(const TransactionFilter()),
                    child: const Text('Clear'),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: FilledButton(
                    onPressed: () {
                      // Keep any text already typed in the search box.
                      widget.onApply(TransactionFilter(
                        type: _type,
                        categoryId: _categoryId,
                        startDate: _range?.start,
                        endDate: _range?.end,
                        searchQuery: widget.current.searchQuery,
                      ));
                    },
                    child: const Text('Apply'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
