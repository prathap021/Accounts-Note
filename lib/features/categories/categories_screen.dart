import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../models/category_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/category_provider.dart';
import '../../providers/transaction_provider.dart';

// Small curated icon set users can assign to custom categories.
const _iconOptions = <String, IconData>{
  'category': Icons.category,
  'restaurant': Icons.restaurant,
  'directions_car': Icons.directions_car,
  'shopping_bag': Icons.shopping_bag,
  'receipt_long': Icons.receipt_long,
  'movie': Icons.movie,
  'local_hospital': Icons.local_hospital,
  'school': Icons.school,
  'work': Icons.work,
  'store': Icons.store,
  'trending_up': Icons.trending_up,
  'flight': Icons.flight,
  'pets': Icons.pets,
  'sports_esports': Icons.sports_esports,
  'home': Icons.home,
};

IconData iconFor(String name) => _iconOptions[name] ?? Icons.category;

class CategoriesScreen extends ConsumerStatefulWidget {
  const CategoriesScreen({super.key});

  @override
  ConsumerState<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends ConsumerState<CategoriesScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Categories'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [Tab(text: 'Expense'), Tab(text: 'Income')],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showCategoryForm(
          context,
          type: _tabController.index == 0 ? TransactionType.expense : TransactionType.income,
        ),
        child: const Icon(Icons.add),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          _CategoryList(type: TransactionType.expense),
          _CategoryList(type: TransactionType.income),
        ],
      ),
    );
  }

  void _showCategoryForm(BuildContext context, {required TransactionType type, CategoryModel? existing}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _CategoryFormSheet(type: type, existing: existing),
    );
  }
}

class _CategoryList extends ConsumerWidget {
  final TransactionType type;
  const _CategoryList({required this.type});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(categoriesStreamProvider(type));

    return categoriesAsync.when(
      data: (categories) => ListView.builder(
        itemCount: categories.length,
        itemBuilder: (context, i) {
          final c = categories[i];
          return ListTile(
            leading: CircleAvatar(
              backgroundColor: Color(c.color).withValues(alpha: 0.15),
              child: Icon(iconFor(c.icon), color: Color(c.color)),
            ),
            title: Text(c.name),
            subtitle: c.isDefault ? const Text('Default category') : null,
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _confirmDelete(context, ref, c),
            ),
            onTap: () => showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              builder: (_) => _CategoryFormSheet(type: type, existing: c),
            ),
          );
        },
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref, CategoryModel category) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove "${category.name}"?'),
        content: Text(category.isDefault
            ? 'This default category will be hidden from pickers but past transactions keep their history.'
            : 'This will permanently delete the category if it has no transactions, otherwise it will be archived.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove')),
        ],
      ),
    );
    if (confirmed != true) return;

    // Cheap heuristic: check if any transaction currently references this
    // category before deciding delete vs archive. Fails safe to "archive"
    // (rather than hard-delete) if the uid is missing or the read fails.
    final uid = ref.read(currentUidProvider);
    var hasTransactions = true;
    if (uid != null) {
      final txs = await ref.read(transactionRepositoryProvider).fetchPage(uid: uid);
      hasTransactions = txs.when(
        success: (list) => list.any((t) => t.categoryId == category.id),
        failure: (_) => true,
      );
    }
    await ref
        .read(categoryActionsProvider.notifier)
        .removeCategory(category, hasTransactions: hasTransactions);
  }
}

class _CategoryFormSheet extends ConsumerStatefulWidget {
  final TransactionType type;
  final CategoryModel? existing;
  const _CategoryFormSheet({required this.type, this.existing});

  @override
  ConsumerState<_CategoryFormSheet> createState() => _CategoryFormSheetState();
}

class _CategoryFormSheetState extends ConsumerState<_CategoryFormSheet> {
  final _nameController = TextEditingController();
  String _icon = 'category';
  Color _color = Colors.blue;

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      _nameController.text = widget.existing!.name;
      _icon = widget.existing!.icon;
      _color = Color(widget.existing!.color);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20, right: 20, top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.existing == null ? 'New Category' : 'Edit Category',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(labelText: 'Category name'),
          ),
          const SizedBox(height: 16),
          const Text('Icon'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final entry in _iconOptions.entries)
                ChoiceChip(
                  label: Icon(entry.value, size: 20),
                  selected: _icon == entry.key,
                  onSelected: (_) => setState(() => _icon = entry.key),
                ),
            ],
          ),
          const SizedBox(height: 16),
          const Text('Color'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final c in Colors.primaries)
                GestureDetector(
                  onTap: () => setState(() => _color = c),
                  child: CircleAvatar(
                    backgroundColor: c,
                    radius: 16,
                    child: _color.toARGB32() == c.toARGB32()
                        ? const Icon(Icons.check, size: 16, color: Colors.white)
                        : null,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () async {
              final name = _nameController.text.trim();
              if (name.isEmpty) return;
              final notifier = ref.read(categoryActionsProvider.notifier);
              if (widget.existing == null) {
                await notifier.addCategory(CategoryModel(
                  id: '',
                  name: name,
                  icon: _icon,
                  color: _color.toARGB32(),
                  type: widget.type,
                  createdAt: DateTime.now(),
                ));
              } else {
                await notifier.updateCategory(
                  widget.existing!.copyWith(name: name, icon: _icon, color: _color.toARGB32()),
                );
              }
              if (!context.mounted) return;
              if (mounted) Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
