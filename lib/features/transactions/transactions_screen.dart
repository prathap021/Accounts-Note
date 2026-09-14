import '../../providers/settings_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../data/repositories/transaction_repository.dart';
import '../../providers/category_provider.dart';
import '../../providers/transaction_provider.dart';
import '../../widgets/transaction_tile.dart';

class TransactionsScreen extends ConsumerStatefulWidget {
  const TransactionsScreen({super.key});

  @override
  ConsumerState<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends ConsumerState<TransactionsScreen> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _updateFilter(TransactionFilter Function(TransactionFilter) update) {
    final current = ref.read(transactionFilterProvider);
    ref.read(transactionFilterProvider.notifier).update(update(current));
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final txsAsync = ref.watch(transactionsStreamProvider);
    final filter = ref.watch(transactionFilterProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: () =>
            context.push('/transaction/add', extra: TransactionType.expense),
        child: const Icon(Icons.add_rounded),
      ),
      body: Column(
        children: [
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Activity',
                          style:
                              Theme.of(context).textTheme.headlineSmall?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.5,
                                  ),
                        ),
                      ),
                      IconButton.filledTonal(
                        onPressed: () => _showFilterSheet(context),
                        icon: const Icon(Icons.tune_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search notes or categories',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: filter.searchQuery?.isNotEmpty ?? false
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded),
                              onPressed: () {
                                _searchController.clear();
                                _updateFilter(
                                  (f) => TransactionFilter(
                                    startDate: f.startDate,
                                    endDate: f.endDate,
                                    type: f.type,
                                    categoryId: f.categoryId,
                                    paymentMethod: f.paymentMethod,
                                  ),
                                );
                              },
                            )
                          : null,
                    ),
                    onChanged: (value) => _updateFilter(
                      (f) => TransactionFilter(
                        startDate: f.startDate,
                        endDate: f.endDate,
                        type: f.type,
                        categoryId: f.categoryId,
                        paymentMethod: f.paymentMethod,
                        searchQuery: value,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: txsAsync.when(
              data: (txs) {
                if (txs.isEmpty) {
                  return const EmptyState(
                    icon: Icons.filter_alt_off_outlined,
                    title: 'Nothing matches',
                    message: 'Try clearing filters or add a new transaction.',
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                  itemCount: txs.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 4),
                  itemBuilder: (context, i) {
                    final tx = txs[i];
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainer,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: scheme.outlineVariant.withValues(alpha: 0.3),
                        ),
                      ),
                      child: TransactionTile(currency: settings.currency, 
                        transaction: tx,
                        onTap: () =>
                            context.push('/transaction/edit', extra: tx),
                        onDelete: () => ref
                            .read(transactionActionsProvider.notifier)
                            .deleteTransaction(tx.id),
                      ),
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => const Center(
                child: Text('Something went wrong. Please try again.'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showFilterSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _FilterSheet(
        current: ref.read(transactionFilterProvider),
        onApply: (filter) {
          ref.read(transactionFilterProvider.notifier).update(filter);
          Navigator.pop(ctx);
        },
      ),
    );
  }
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
          start: widget.current.startDate!, end: widget.current.endDate!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(categoriesStreamProvider(_type));

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 8,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Filter activity',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 16),
          SegmentedButton<TransactionType?>(
            segments: const [
              ButtonSegment(value: null, label: Text('All')),
              ButtonSegment(
                  value: TransactionType.income, label: Text('Income')),
              ButtonSegment(
                  value: TransactionType.expense, label: Text('Expense')),
            ],
            selected: {_type},
            onSelectionChanged: (s) => setState(() {
              _type = s.first;
              _categoryId = null;
            }),
          ),
          const SizedBox(height: 16),
          categoriesAsync.when(
            data: (categories) => Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('All categories'),
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
          const SizedBox(height: 16),
          OutlinedButton.icon(
            icon: const Icon(Icons.date_range_rounded),
            label: Text(_range == null
                ? 'Select date range'
                : '${_range!.start.toLocal().toString().split(' ').first} - ${_range!.end.toLocal().toString().split(' ').first}'),
            onPressed: () async {
              final picked = await showDateRangePicker(
                context: context,
                firstDate: DateTime(2020),
                lastDate: DateTime(2100),
                initialDateRange: _range,
              );
              if (picked != null) setState(() => _range = picked);
            },
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => widget.onApply(const TransactionFilter()),
                  child: const Text('Clear'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () {
                    widget.onApply(TransactionFilter(
                      type: _type,
                      categoryId: _categoryId,
                      startDate: _range?.start,
                      endDate: _range?.end,
                    ));
                  },
                  child: const Text('Apply'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
