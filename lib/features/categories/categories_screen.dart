import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../core/constants/category_icons.dart';
import '../../core/theme/app_theme.dart';
import '../../models/category_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/category_provider.dart';
import '../../providers/transaction_provider.dart';

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
    // The FAB adds to whichever tab is showing, so it has to follow the tab.
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) setState(() {});
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  TransactionType get _activeType =>
      _tabController.index == 0 ? TransactionType.expense : TransactionType.income;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Categories'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.gutter,
              0,
              AppSpacing.gutter,
              AppSpacing.md,
            ),
            child: Container(
              decoration: BoxDecoration(
                color: scheme.surfaceContainer,
                borderRadius: BorderRadius.circular(AppRadii.control),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: TabBar(
                controller: _tabController,
                dividerColor: Colors.transparent,
                indicatorSize: TabBarIndicatorSize.tab,
                indicator: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(AppRadii.control - 3),
                ),
                indicatorPadding: const EdgeInsets.all(3),
                tabs: const [Tab(text: 'Expense'), Tab(text: 'Income')],
              ),
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab-categories',
        onPressed: () => _showCategoryForm(context, type: _activeType),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New category'),
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

  void _showCategoryForm(
    BuildContext context, {
    required TransactionType type,
    CategoryModel? existing,
  }) {
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final categoriesAsync = ref.watch(categoriesStreamProvider(type));

    return categoriesAsync.when(
      data: (categories) {
        if (categories.isEmpty) {
          return EmptyState(
            icon: Icons.category_outlined,
            title: 'No categories yet',
            message:
                'Create a ${type == TransactionType.income ? 'income' : 'expense'} category to organise your entries.',
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.gutter,
            AppSpacing.sm,
            AppSpacing.gutter,
            AppSpacing.scrollBottom,
          ),
          itemCount: categories.length,
          separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
          itemBuilder: (context, i) {
            final c = categories[i];
            final color = Color(c.color);

            return AppCard(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.md,
              ),
              onTap: () => showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                builder: (_) => _CategoryFormSheet(type: type, existing: c),
              ),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Icon(iconFor(c.icon), color: color, size: 20),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          c.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall,
                        ),
                        if (c.isDefault)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              'Default category',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Remove category',
                    icon: Icon(
                      Icons.delete_outline_rounded,
                      size: 20,
                      color: scheme.onSurfaceVariant,
                    ),
                    onPressed: () => _confirmDelete(context, ref, c),
                  ),
                ],
              ),
            );
          },
        );
      },
      loading: () => ListView(
        padding: const EdgeInsets.all(AppSpacing.gutter),
        children: const [
          SkeletonBox(height: 66, radius: AppRadii.card),
          SizedBox(height: AppSpacing.sm),
          SkeletonBox(height: 66, radius: AppRadii.card),
          SizedBox(height: AppSpacing.sm),
          SkeletonBox(height: 66, radius: AppRadii.card),
        ],
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(AppSpacing.gutter),
        child: Center(
          child: AppErrorState(
            message: "We couldn't load your categories.",
            onRetry: () => ref.invalidate(categoriesStreamProvider(type)),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    CategoryModel category,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove "${category.name}"?'),
        content: Text(category.isDefault
            ? 'This default category will be hidden from pickers but past transactions keep their history.'
            : 'This will permanently delete the category if it has no transactions, otherwise it will be archived.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
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
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      _nameController.text = widget.existing!.name;
      _icon = widget.existing!.icon;
      _color = Color(widget.existing!.color);
    }
    _nameController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Give this category a name');
      return;
    }
    final notifier = ref.read(categoryActionsProvider.notifier);
    final navigator = Navigator.of(context);
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
        widget.existing!.copyWith(
          name: name,
          icon: _icon,
          color: _color.toARGB32(),
        ),
      );
    }
    if (mounted) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final previewName =
        _nameController.text.trim().isEmpty ? 'Category name' : _nameController.text.trim();

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
            Text(
              widget.existing == null ? 'New category' : 'Edit category',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.xl),
            // Live preview so the icon + colour choice is obvious before saving.
            AppCard(
              color: _color.withValues(alpha: 0.08),
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: _color.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(iconFor(_icon), color: _color),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      previewName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  Text(
                    widget.type == TransactionType.income ? 'Income' : 'Expense',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            TextField(
              controller: _nameController,
              autofocus: widget.existing == null,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: 'Category name',
                errorText: _error,
              ),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
            ),
            const SizedBox(height: AppSpacing.xl),
            const SectionLabel('Icon'),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final entry in kCategoryIcons.entries)
                  _SelectableSquare(
                    selected: _icon == entry.key,
                    color: _color,
                    onTap: () => setState(() => _icon = entry.key),
                    child: Icon(
                      entry.value,
                      size: 20,
                      color: _icon == entry.key ? _color : scheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            const SectionLabel('Colour'),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final c in Colors.primaries)
                  GestureDetector(
                    onTap: () => setState(() => _color = c),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _color.toARGB32() == c.toARGB32()
                              ? scheme.onSurface
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      child: _color.toARGB32() == c.toARGB32()
                          ? const Icon(Icons.check_rounded,
                              size: 18, color: Colors.white)
                          : null,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.xxl),
            // This Column aligns to start, so the button needs an explicit
            // full width rather than relying on the button theme.
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _save,
                child: Text(
                  widget.existing == null ? 'Create category' : 'Save changes',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SelectableSquare extends StatelessWidget {
  final bool selected;
  final Color color;
  final VoidCallback onTap;
  final Widget child;

  const _SelectableSquare({
    required this.selected,
    required this.color,
    required this.onTap,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(13),
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.14) : scheme.surfaceContainer,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(
            color: selected ? color.withValues(alpha: 0.6) : scheme.outlineVariant,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Center(child: child),
      ),
    );
  }
}
