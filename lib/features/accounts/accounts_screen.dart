import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/utils/result.dart';
import '../../core/utils/snackbar_helper.dart';
import '../../models/account_model.dart';
import '../../providers/account_provider.dart';
import '../../providers/settings_provider.dart';

/// Opens the add/edit account form. Completes with the saved account.
Future<AccountModel?> showAccountForm(
  BuildContext context, {
  AccountModel? existing,
}) => showModalBottomSheet<AccountModel>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) => _AccountFormSheet(existing: existing),
);

/// Opens the transfer form. Completes with the saved transfer.
Future<TransferModel?> showTransferForm(BuildContext context) =>
    showModalBottomSheet<TransferModel>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _TransferFormSheet(),
    );

String _errorOf(AsyncValue<void> state) =>
    state is AsyncError && state.error is AppFailure
    ? (state.error as AppFailure).userMessage
    : 'Something went wrong. Please try again.';

/// Cash, bank, UPI and wallet accounts with their balances, and the
/// transfers between them.
class AccountsScreen extends ConsumerWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountsAsync = ref.watch(accountsStreamProvider);
    final balances = ref.watch(accountBalancesProvider);
    final transfers = ref.watch(transfersStreamProvider).asData?.value ?? [];
    final currency = ref.watch(settingsProvider).currency;
    final theme = Theme.of(context);
    final hasAccounts = accountsAsync.asData?.value.isNotEmpty ?? false;

    return Scaffold(
      appBar: AppBar(title: const Text('Accounts')),
      floatingActionButton: hasAccounts
          ? FloatingActionButton.extended(
              heroTag: 'fab-accounts',
              onPressed: () => showAccountForm(context),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add account'),
            )
          : null,
      body: accountsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: AppErrorState(
            message: "We couldn't load your accounts.",
            onRetry: () => ref.invalidate(accountsStreamProvider),
          ),
        ),
        data: (accounts) {
          if (accounts.isEmpty) {
            return Center(
              child: SingleChildScrollView(
                child: EmptyState(
                  icon: Icons.account_balance_outlined,
                  title: 'No accounts yet',
                  message:
                      'Add your cash, bank, UPI or wallet accounts with what '
                      'is in them today. Pick one when you log an entry to '
                      'see each balance, and move money between them with '
                      'transfers.',
                  actionLabel: 'Add account',
                  onAction: () => showAccountForm(context),
                ),
              ),
            );
          }
          final total = accounts.fold<double>(
            0,
            (sum, a) => sum + (balances[a.id] ?? 0),
          );
          return ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.gutter,
              AppSpacing.sm,
              AppSpacing.gutter,
              AppSpacing.scrollBottom,
            ),
            children: [
              AppCard(
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Total in accounts',
                            style: theme.textTheme.labelMedium,
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            CurrencyFormatter.format(
                              total,
                              currencyCode: currency,
                            ),
                            key: const Key('accounts-total'),
                            style: theme.textTheme.headlineSmall,
                          ),
                        ],
                      ),
                    ),
                    if (accounts.length > 1)
                      FilledButton.tonalIcon(
                        onPressed: () => showTransferForm(context),
                        icon: const Icon(Icons.swap_horiz_rounded),
                        label: const Text('Transfer'),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              const SectionLabel('Your accounts'),
              AppCard(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                child: Column(
                  children: [
                    for (var i = 0; i < accounts.length; i++) ...[
                      if (i > 0) const Divider(height: 1),
                      AccountBalanceTile(
                        account: accounts[i],
                        balance: balances[accounts[i].id] ?? 0,
                        currency: currency,
                        onTap: () =>
                            showAccountForm(context, existing: accounts[i]),
                      ),
                    ],
                  ],
                ),
              ),
              if (transfers.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xl),
                const SectionLabel('Transfers'),
                AppCard(
                  padding: const EdgeInsets.symmetric(
                    vertical: AppSpacing.xs,
                  ),
                  child: Column(
                    children: [
                      for (var i = 0; i < transfers.length; i++) ...[
                        if (i > 0) const Divider(height: 1),
                        _TransferTile(
                          transfer: transfers[i],
                          currency: currency,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// One account and its balance. Used here and on the dashboard.
class AccountBalanceTile extends StatelessWidget {
  const AccountBalanceTile({
    super.key,
    required this.account,
    required this.balance,
    required this.currency,
    this.onTap,
  });

  final AccountModel account;
  final double balance;
  final String currency;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      key: Key('account-${account.id}'),
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: theme.colorScheme.primaryContainer,
        foregroundColor: theme.colorScheme.onPrimaryContainer,
        child: Icon(account.kind.icon, size: 20),
      ),
      title: Text(account.name),
      subtitle: Text(account.kind.label),
      trailing: Text(
        CurrencyFormatter.format(balance, currencyCode: currency),
        style: theme.textTheme.titleSmall?.copyWith(
          color: balance < 0 ? AppColors.expense : null,
        ),
      ),
    );
  }
}

class _TransferTile extends ConsumerWidget {
  const _TransferTile({required this.transfer, required this.currency});

  final TransferModel transfer;
  final String currency;

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete transfer?'),
        content: const Text(
          'Both balances go back to what they were before it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final done = await ref
        .read(accountActionsProvider.notifier)
        .deleteTransfer(transfer.id);
    if (!context.mounted) return;
    if (done) {
      SnackbarHelper.showSuccess(context, 'Transfer deleted');
    } else {
      SnackbarHelper.showError(context, _errorOf(ref.read(accountActionsProvider)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final when = DateFormat('d MMM yyyy').format(transfer.date);
    return ListTile(
      leading: const Icon(Icons.swap_horiz_rounded),
      title: Text('${transfer.fromAccountName} → ${transfer.toAccountName}'),
      subtitle: Text(
        transfer.note == null || transfer.note!.isEmpty
            ? when
            : '$when · ${transfer.note}',
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            CurrencyFormatter.format(transfer.amount, currencyCode: currency),
            style: theme.textTheme.titleSmall,
          ),
          IconButton(
            tooltip: 'Delete transfer',
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: () => _delete(context, ref),
          ),
        ],
      ),
    );
  }
}

/// Parses a money amount typed by the user; null when it isn't one.
double? _parseAmount(String text) =>
    double.tryParse(text.trim().replaceAll(',', ''));

class _AccountFormSheet extends ConsumerStatefulWidget {
  const _AccountFormSheet({this.existing});

  final AccountModel? existing;

  @override
  ConsumerState<_AccountFormSheet> createState() => _AccountFormSheetState();
}

class _AccountFormSheetState extends ConsumerState<_AccountFormSheet> {
  late final _name = TextEditingController(text: widget.existing?.name);
  late final _opening = TextEditingController(
    text: widget.existing == null || widget.existing!.openingBalance == 0
        ? ''
        : widget.existing!.openingBalance.toStringAsFixed(2),
  );
  late AccountKind _kind = widget.existing?.kind ?? AccountKind.bank;
  String? _nameError;
  String? _openingError;
  String? _saveError;
  bool _saving = false;

  bool get _isEditing => widget.existing != null;

  @override
  void dispose() {
    _name.dispose();
    _opening.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final openingText = _opening.text.trim();
    final opening = openingText.isEmpty ? 0.0 : _parseAmount(openingText);
    setState(() {
      _nameError = name.isEmpty ? 'Enter a name' : null;
      _openingError =
          opening == null || opening.abs() >= AccountModel.maxAmount
          ? 'Enter a valid amount'
          : null;
      _saveError = null;
    });
    if (_nameError != null || _openingError != null) return;

    setState(() => _saving = true);
    final n = ref.read(accountActionsProvider.notifier);
    final navigator = Navigator.of(context);
    AccountModel? saved;
    final existing = widget.existing;
    if (existing == null) {
      saved = await n.addAccount(
        AccountModel(
          id: '',
          name: name,
          kind: _kind,
          openingBalance: opening!,
          createdAt: DateTime.now(),
        ),
      );
    } else {
      final updated = existing.copyWith(
        name: name,
        kind: _kind,
        openingBalance: opening,
      );
      saved = await n.updateAccount(updated) ? updated : null;
    }
    if (!mounted) return;
    if (saved == null) {
      setState(() {
        _saving = false;
        _saveError = _errorOf(ref.read(accountActionsProvider));
      });
      return;
    }
    navigator.pop(saved);
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete account?'),
        content: const Text(
          'Entries and transfers that used it stay in your history with its '
          'name, but no longer count towards any balance.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final navigator = Navigator.of(context);
    final done = await ref
        .read(accountActionsProvider.notifier)
        .deleteAccount(widget.existing!.id);
    if (!mounted) return;
    if (done) {
      navigator.pop();
    } else {
      setState(() => _saveError = _errorOf(ref.read(accountActionsProvider)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currency = ref.watch(settingsProvider).currency;
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
            Row(
              children: [
                Expanded(
                  child: Text(
                    _isEditing ? 'Edit account' : 'New account',
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                if (_isEditing)
                  IconButton(
                    tooltip: 'Delete account',
                    icon: const Icon(Icons.delete_outline_rounded),
                    onPressed: _saving ? null : _delete,
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            Wrap(
              spacing: AppSpacing.sm,
              children: [
                for (final k in AccountKind.values)
                  ChoiceChip(
                    avatar: Icon(k.icon, size: 18),
                    label: Text(k.label),
                    selected: _kind == k,
                    onSelected: (_) => setState(() => _kind = k),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              key: const Key('account-name'),
              controller: _name,
              autofocus: !_isEditing,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              inputFormatters: [
                LengthLimitingTextInputFormatter(AccountModel.maxNameLength),
              ],
              decoration: InputDecoration(
                labelText: 'Account name',
                hintText: 'e.g. SBI savings, Cash in hand',
                errorText: _nameError,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              key: const Key('account-opening'),
              controller: _opening,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              decoration: InputDecoration(
                labelText: 'Balance when you start tracking',
                helperText: 'What is in it today. Leave empty for zero.',
                prefixText: '${CurrencyFormatter.symbolFor(currency)} ',
                errorText: _openingError,
              ),
            ),
            if (_saveError != null) ...[
              const SizedBox(height: AppSpacing.lg),
              Text(
                _saveError!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.xxl),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(_isEditing ? 'Save changes' : 'Add account'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TransferFormSheet extends ConsumerStatefulWidget {
  const _TransferFormSheet();

  @override
  ConsumerState<_TransferFormSheet> createState() => _TransferFormSheetState();
}

class _TransferFormSheetState extends ConsumerState<_TransferFormSheet> {
  final _amount = TextEditingController();
  final _note = TextEditingController();
  String? _from;
  String? _to;
  DateTime _date = DateTime.now();
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(
        () => _date = DateTime(
          picked.year,
          picked.month,
          picked.day,
          _date.hour,
          _date.minute,
        ),
      );
    }
  }

  Future<void> _save(Map<String, AccountModel> lookup) async {
    final amount = _parseAmount(_amount.text);
    final from = lookup[_from];
    final to = lookup[_to];
    String? error;
    if (from == null || to == null) {
      error = 'Choose both accounts.';
    } else if (from.id == to.id) {
      error = 'Choose two different accounts.';
    } else if (amount == null ||
        amount <= 0 ||
        amount >= AccountModel.maxAmount) {
      error = 'Enter an amount above zero.';
    }
    setState(() => _error = error);
    if (error != null) return;

    setState(() => _saving = true);
    final navigator = Navigator.of(context);
    final note = _note.text.trim();
    final saved = await ref
        .read(accountActionsProvider.notifier)
        .addTransfer(
          TransferModel(
            id: '',
            fromAccountId: from!.id,
            toAccountId: to!.id,
            fromAccountName: from.name,
            toAccountName: to.name,
            amount: amount!,
            date: _date,
            note: note.isEmpty ? null : note,
            createdAt: DateTime.now(),
          ),
        );
    if (!mounted) return;
    if (saved == null) {
      setState(() {
        _saving = false;
        _error = _errorOf(ref.read(accountActionsProvider));
      });
      return;
    }
    SnackbarHelper.showSuccess(
      context,
      'Moved ${CurrencyFormatter.format(amount, currencyCode: ref.read(settingsProvider).currency)} '
      'to ${to.name}',
    );
    navigator.pop(saved);
  }

  Widget _picker(
    String label,
    String? value,
    List<AccountModel> accounts,
    ValueChanged<String?> onChanged,
    Key key,
  ) => DropdownButtonFormField<String>(
    key: key,
    initialValue: value,
    isExpanded: true,
    decoration: InputDecoration(labelText: label),
    items: [
      for (final a in accounts)
        DropdownMenuItem(
          value: a.id,
          child: Row(
            children: [
              Icon(a.kind.icon, size: 18),
              const SizedBox(width: AppSpacing.sm),
              Flexible(child: Text(a.name, overflow: TextOverflow.ellipsis)),
            ],
          ),
        ),
    ],
    onChanged: onChanged,
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accounts = ref.watch(accountsStreamProvider).asData?.value ?? [];
    final lookup = ref.watch(accountLookupProvider);
    final currency = ref.watch(settingsProvider).currency;
    _from ??= accounts.isNotEmpty ? accounts.first.id : null;
    _to ??= accounts.length > 1 ? accounts[1].id : null;

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
            Text('Transfer money', style: theme.textTheme.titleLarge),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Moving money between your own accounts is not income or an '
              'expense, so it does not change your totals.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.lg),
            _picker(
              'From',
              _from,
              accounts,
              (v) => setState(() => _from = v),
              const Key('transfer-from'),
            ),
            const SizedBox(height: AppSpacing.md),
            _picker(
              'To',
              _to,
              accounts,
              (v) => setState(() => _to = v),
              const Key('transfer-to'),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              key: const Key('transfer-amount'),
              controller: _amount,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Amount',
                prefixText: '${CurrencyFormatter.symbolFor(currency)} ',
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _note,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Note (optional)',
                hintText: 'e.g. ATM withdrawal',
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_rounded),
              title: const Text('Date'),
              trailing: Text(DateFormat('d MMM yyyy').format(_date)),
              onTap: _pickDate,
            ),
            if (_error != null)
              Text(
                _error!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : () => _save(lookup),
                child: const Text('Move money'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
