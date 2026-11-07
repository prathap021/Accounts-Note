import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/currency_formatter.dart';
import '../../data/repositories/recurring_repository.dart';
import '../../models/recurring_rule.dart';
import '../../providers/auth_provider.dart';
import '../../providers/automation_provider.dart';
import '../../providers/settings_provider.dart';

/// Every repeating transaction, when it is next due, and controls to pause,
/// resume or stop it. New ones are made from the add form's Repeat switch.
class RecurringScreen extends ConsumerWidget {
  const RecurringScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rules = ref.watch(recurringRulesProvider);
    final currency = ref.watch(settingsProvider).currency;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Recurring'),
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/dashboard'),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab-recurring',
        icon: const Icon(Icons.add_rounded),
        label: const Text('New'),
        onPressed: () =>
            context.push('/transaction/add', extra: TransactionType.expense),
      ),
      body: rules.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const AppErrorState(
          message: "We couldn't load your recurring transactions.",
        ),
        data: (list) => list.isEmpty
            ? const Center(
                child: SingleChildScrollView(
                  child: EmptyState(
                    icon: Icons.repeat_rounded,
                    title: 'Nothing repeats yet',
                    message:
                        'Add a transaction and turn on Repeat for salary, '
                        'rent, EMIs or subscriptions. They are added '
                        'automatically when due.',
                  ),
                ),
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.gutter,
                  AppSpacing.sm,
                  AppSpacing.gutter,
                  AppSpacing.scrollBottom,
                ),
                itemCount: list.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: AppSpacing.md),
                itemBuilder: (_, i) =>
                    _RuleCard(rule: list[i], currency: currency),
              ),
      ),
    );
  }
}

class _RuleCard extends ConsumerWidget {
  const _RuleCard({required this.rule, required this.currency});

  final RecurringRule rule;
  final String currency;

  Future<void> _save(WidgetRef ref, RecurringRule updated) async {
    final uid = ref.read(currentUidProvider);
    if (uid == null) return;
    await ref.read(recurringRepositoryProvider).save(uid, updated);
    await ref.read(recurringRunnerProvider).scheduleBillReminders();
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Stop repeating?'),
        content: const Text(
          'No more entries will be added. The ones already added stay.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Stop'),
          ),
        ],
      ),
    );
    final uid = ref.read(currentUidProvider);
    if (ok != true || uid == null) return;
    await ref.read(recurringRepositoryProvider).delete(uid, rule.id);
    await ref.read(recurringRunnerProvider).scheduleBillReminders();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final income = rule.type == TransactionType.income;
    final next = rule.nextOccurrence();
    final title = rule.note?.isNotEmpty == true
        ? rule.note!
        : rule.categoryName;
    final status = !rule.active
        ? 'Paused'
        : next == null
        ? 'Finished'
        : 'Next: ${DateFormat('EEE, d MMM yyyy').format(next)}';

    return AppCard(
      key: Key('rule-${rule.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                income ? Icons.south_west_rounded : Icons.north_east_rounded,
                color: income ? AppColors.income : AppColors.expense,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
              Text(
                CurrencyFormatter.format(rule.amount, currencyCode: currency),
                style: theme.textTheme.titleMedium,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '${rule.frequency.label} · ${rule.categoryName}'
            '${rule.endDate == null ? '' : ' · until ${DateFormat('d MMM yyyy').format(rule.endDate!)}'}',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            status,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: () =>
                    _save(ref, rule.copyWith(active: !rule.active)),
                icon: Icon(
                  rule.active ? Icons.pause_rounded : Icons.play_arrow_rounded,
                ),
                label: Text(rule.active ? 'Pause' : 'Resume'),
              ),
              TextButton.icon(
                onPressed: () => _delete(context, ref),
                icon: const Icon(Icons.stop_circle_outlined),
                label: const Text('Stop'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
