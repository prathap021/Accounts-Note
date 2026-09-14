import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/result.dart';
import '../../core/utils/snackbar_helper.dart';
import '../../models/category_model.dart';
import '../../models/transaction_model.dart';
import '../../providers/category_provider.dart';
import '../../providers/dashboard_provider.dart';
import '../../providers/transaction_provider.dart';

const _paymentMethods = ['Cash', 'Card', 'UPI', 'Bank Transfer', 'Wallet', 'Other'];

class AddEditTransactionScreen extends ConsumerStatefulWidget {
  final TransactionType initialType;
  final TransactionModel? existing;

  const AddEditTransactionScreen({
    super.key,
    this.initialType = TransactionType.expense,
    this.existing,
  });

  @override
  ConsumerState<AddEditTransactionScreen> createState() =>
      _AddEditTransactionScreenState();
}

class _AddEditTransactionScreenState
    extends ConsumerState<AddEditTransactionScreen> {
  final _formKey = GlobalKey<FormState>();
  late TransactionType _type;
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  CategoryModel? _selectedCategory;
  DateTime _date = DateTime.now();
  String _paymentMethod = _paymentMethods.first;
  bool _saving = false;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _type = existing?.type ?? widget.initialType;
    if (existing != null) {
      _amountController.text = existing.amount.toStringAsFixed(2);
      _noteController.text = existing.note ?? '';
      _date = existing.date;
      _paymentMethod = existing.paymentMethod ?? _paymentMethods.first;
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(categoriesStreamProvider(_type));
    final color =
        _type == TransactionType.income ? AppColors.income : AppColors.expense;

    // Pre-select the existing category once the stream resolves.
    categoriesAsync.whenData((categories) {
      if (_selectedCategory == null) {
        if (widget.existing != null) {
          _selectedCategory = categories
              .where((c) => c.id == widget.existing!.categoryId)
              .firstOrNull;
        }
        _selectedCategory ??= categories.firstOrNull;
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Transaction' : 'Add Transaction'),
        actions: [
          if (_isEditing)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: _confirmDelete,
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SegmentedButton<TransactionType>(
              segments: const [
                ButtonSegment(
                    value: TransactionType.expense, label: Text('Expense')),
                ButtonSegment(
                    value: TransactionType.income, label: Text('Income')),
              ],
              selected: {_type},
              onSelectionChanged: (s) {
                setState(() {
                  _type = s.first;
                  _selectedCategory = null;
                });
              },
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _amountController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              style: TextStyle(
                  fontSize: 28, fontWeight: FontWeight.bold, color: color),
              decoration:
                  const InputDecoration(prefixText: '₹ ', labelText: 'Amount'),
              validator: (v) {
                final val = double.tryParse(v ?? '');
                if (val == null || val <= 0) return 'Enter a valid amount';
                return null;
              },
            ),
            const SizedBox(height: 16),
            categoriesAsync.when(
              data: (categories) => DropdownButtonFormField<CategoryModel>(
                initialValue: _selectedCategory,
                decoration: const InputDecoration(labelText: 'Category'),
                items: [
                  for (final c in categories)
                    DropdownMenuItem(value: c, child: Text(c.name)),
                ],
                onChanged: (c) => setState(() => _selectedCategory = c),
                validator: (v) => v == null ? 'Select a category' : null,
              ),
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => const Text(
                'Something went wrong. Please try again.',
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Date & time'),
              subtitle: Text(_date.toLocal().toString().substring(0, 16)),
              trailing: const Icon(Icons.calendar_today_outlined),
              onTap: _pickDateTime,
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _paymentMethod,
              decoration: const InputDecoration(labelText: 'Payment method'),
              items: [
                for (final m in _paymentMethods)
                  DropdownMenuItem(value: m, child: Text(m)),
              ],
              onChanged: (v) =>
                  setState(() => _paymentMethod = v ?? _paymentMethod),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _noteController,
              decoration: const InputDecoration(labelText: 'Note (optional)'),
              maxLines: 2,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(_isEditing ? 'Save Changes' : 'Add Transaction'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2015),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) return;
    final time =
        await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_date));
    if (time == null) return;
    setState(() {
      _date = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _selectedCategory == null) return;
    setState(() => _saving = true);

    final amount = double.parse(_amountController.text);
    final now = DateTime.now();
    final tx = TransactionModel(
      id: widget.existing?.id ?? '',
      type: _type,
      amount: amount,
      categoryId: _selectedCategory!.id,
      categoryName: _selectedCategory!.name,
      note: _noteController.text.trim().isEmpty
          ? null
          : _noteController.text.trim(),
      date: _date,
      paymentMethod: _paymentMethod,
      createdAt: widget.existing?.createdAt ?? now,
      updatedAt: now,
    );

    final notifier = ref.read(transactionActionsProvider.notifier);
    final success = _isEditing
        ? await notifier.updateTransaction(tx)
        : await notifier.addTransaction(tx) != false;

    if (!mounted) return;
    setState(() => _saving = false);

    if (success) {
      ref.invalidate(dashboardSummaryProvider);
      Navigator.of(context).pop();
    } else {
      final err = ref.read(transactionActionsProvider);
      final failure = err is AsyncError && err.error is AppFailure
          ? err.error as AppFailure
          : null;
      final msg = failure?.userMessage ?? 'Something went wrong. Please try again.';
      SnackbarHelper.showError(context, msg);
    }
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete transaction?'),
        content: const Text('This action cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed == true && widget.existing != null && mounted) {
      await ref
          .read(transactionActionsProvider.notifier)
          .deleteTransaction(widget.existing!.id);
      ref.invalidate(dashboardSummaryProvider);
      if (mounted) Navigator.of(context).pop();
    }
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
