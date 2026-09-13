import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_constants.dart';
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
    final txsAsync = ref.watch(transactionsStreamProvider);
    final filter = ref.watch(transactionFilterProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Transactions'),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: () => _showFilterSheet(context),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search transactions...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: filter.searchQuery?.isNotEmpty ?? false
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          _updateFilter((f) => TransactionFilter(
                                startDate: f.startDate,
                                endDate: f.endDate,
                                type: f.type,
                                categoryId: f.categoryId,
                                paymentMethod: f.paymentMethod,
                              ));
                        },
                      )
                    : null,
              ),
              onChanged: (value) => _updateFilter((f) => TransactionFilter(
                    startDate: f.startDate,
                    endDate: f.endDate,
                    type: f.type,
                    categoryId: f.categoryId,
                    paymentMethod: f.paymentMethod,
                    searchQuery: value,
                  )),
            ),
          ),
          Expanded(
            child: txsAsync.when(
              data: (txs) {
                if (txs.isEmpty) {
                  return const Center(child: Text('No transactions match your filters.'));
                }
                return ListView.builder(
                  itemCount: txs.length,
                  itemBuilder: (context, i) {
                    final tx = txs[i];
                    return TransactionTile(
                      transaction: tx,
                      onTap: () => context.push('/transaction/edit', extra: tx),
                      onDelete: () =>
                          ref.read(transactionActionsProvider.notifier).deleteTransaction(tx.id),
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/transaction/add', extra: TransactionType.expense),
        child: const Icon(Icons.add),
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
      _range = DateTimeRange(start: widget.current.startDate!, end: widget.current.endDate!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(categoriesStreamProvider(_type));

    return Padding(
      padding: EdgeInsets.only(
        left: 20, right: 20, top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Filter Transactions', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          SegmentedButton<TransactionType?>(
            segments: const [
              ButtonSegment(value: null, label: Text('All')),
              ButtonSegment(value: TransactionType.income, label: Text('Income')),
              ButtonSegment(value: TransactionType.expense, label: Text('Expense')),
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
            icon: const Icon(Icons.date_range),
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
                  onPressed: () {
                    widget.onApply(const TransactionFilter());
                  },
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
