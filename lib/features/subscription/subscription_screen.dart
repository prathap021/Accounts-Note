import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/snackbar_helper.dart';
import '../../models/daily_usage.dart';
import '../../models/subscription_plan.dart';
import '../../models/subscription_status.dart';
import '../../providers/settings_provider.dart';
import '../../providers/subscription_provider.dart';

/// The three monthly plans, what the user is on, and how much of today's
/// allowance is left.
class SubscriptionScreen extends ConsumerWidget {
  const SubscriptionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ui = ref.watch(subscriptionControllerProvider);
    final status = ref.watch(subscriptionStatusProvider);
    final plan = ref.watch(currentPlanProvider);
    final usage = ref.watch(todayUsageProvider);
    final currency = ref.watch(settingsProvider).currency;
    final controller = ref.read(subscriptionControllerProvider.notifier);

    ref.listen<SubscriptionUiState>(subscriptionControllerProvider, (
      prev,
      next,
    ) {
      final notice = next.notice;
      if (notice == null || identical(notice, prev?.notice)) return;
      if (notice.isError) {
        SnackbarHelper.showError(context, notice.message);
      } else {
        SnackbarHelper.showSuccess(context, notice.message);
      }
    });

    final storeName = Platform.isIOS ? 'App Store' : 'Google Play';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Subscription'),
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/dashboard');
            }
          },
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.gutter,
          AppSpacing.sm,
          AppSpacing.gutter,
          AppSpacing.xxl,
        ),
        children: [
          _StatusCard(status: status, plan: plan, usage: usage),
          const SizedBox(height: AppSpacing.xxl),
          const SectionLabel('Plans'),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<BillingPeriod>(
              key: const Key('billing-period'),
              segments: [
                for (final p in BillingPeriod.values)
                  ButtonSegment(
                    value: p,
                    label: Text(
                      p == BillingPeriod.yearly
                          ? 'Yearly · save ${SubscriptionPlan.yearlySaving(currency)}'
                          : p.label,
                    ),
                  ),
              ],
              selected: {ui.period},
              showSelectedIcon: false,
              onSelectionChanged: (s) => controller.selectPeriod(s.first),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          if (!ui.loading && !ui.storeAvailable) ...[
            _Notice(
              icon: Icons.storefront_outlined,
              text:
                  'Purchases are not available on this device. Make sure '
                  "you're signed in to $storeName, then try again.",
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          for (final p in SubscriptionPlan.paid) ...[
            _PlanCard(
              key: Key('plan-${p.name}'),
              plan: p,
              price: ui.priceFor(p, currency: currency),
              period: ui.period,
              saving: ui.period == BillingPeriod.yearly
                  ? ui.yearlySavingFor(p, currency: currency)
                  : null,
              current: plan,
              currentPeriod: SubscriptionPlan.periodOf(status.productId),
              busy: ui.purchasing == p,
              enabled: !ui.busy && !ui.loading,
              onPressed: () => controller.buy(p),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          Text(
            'Free: ${_count(SubscriptionPlan.free.monthlyLimit)} transactions '
            'a month, income or expense in any mix.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              OutlinedButton.icon(
                onPressed: ui.busy ? null : controller.restore,
                icon: ui.restoring
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.restore_rounded),
                label: const Text('Restore purchases'),
              ),
              if (status.plan.isPaid && status.platform != null)
                TextButton.icon(
                  onPressed: () => launchUrl(
                    Uri.parse(
                      AppLinks.manageSubscription(
                        platform: status.platform!,
                        productId: status.productId,
                      ),
                    ),
                    mode: LaunchMode.externalApplication,
                  ),
                  icon: const Icon(Icons.open_in_new_rounded),
                  label: const Text('Manage or cancel'),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'Plans renew every month or every year, as chosen, until '
            'cancelled. You can cancel at any time in your $storeName '
            'subscriptions; cancel at least 24 hours before the renewal date '
            'to avoid being charged for the next period. Payment is charged '
            "to your $storeName account. Each plan's monthly transactions "
            "are shared out evenly by day, and each day's allowance resets at "
            'midnight; deleting an entry does not give it back.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

/// 900 → "900", 3000 → "3,000".
String _count(int n) => NumberFormat.decimalPattern().format(n);

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.status,
    required this.plan,
    required this.usage,
  });

  final SubscriptionStatus status;
  final SubscriptionPlan plan;
  final DailyUsage usage;

  String _statusLine() {
    final date = status.expiresAt == null
        ? null
        : DateFormat.yMMMd().format(status.expiresAt!);
    if (!status.plan.isPaid) return 'No subscription';
    return switch (status.state) {
      SubscriptionState.active when status.autoRenewing && plan.isPaid =>
        'Renews on $date',
      SubscriptionState.active || SubscriptionState.canceled when plan.isPaid =>
        'Cancelled · ${status.plan.title} until $date',
      SubscriptionState.grace =>
        'Payment problem: update your payment method to keep '
            '${status.plan.title}',
      SubscriptionState.onHold =>
        'On hold: the last payment failed. Free limits apply until it is '
            'fixed.',
      SubscriptionState.paused => 'Paused. Free limits apply until it resumes.',
      _ => '${status.plan.title} ended${date == null ? '' : ' on $date'}',
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'CURRENT PLAN',
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              Icon(
                plan.isPaid
                    ? Icons.workspace_premium_rounded
                    : Icons.person_outline_rounded,
                color: scheme.primary,
              ),
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                child: Text(plan.title, style: theme.textTheme.headlineSmall),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            _statusLine(),
            key: const Key('subscription-status'),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Text('Today', style: theme.textTheme.titleSmall),
          const SizedBox(height: AppSpacing.md),
          _UsageBar(
            label: 'Transactions',
            used: usage.total,
            limit: plan.dailyLimit,
            color: AppColors.primary,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '${usage.income} income · ${usage.expense} expense',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _UsageBar extends StatelessWidget {
  const _UsageBar({
    required this.label,
    required this.used,
    required this.limit,
    required this.color,
  });

  final String label;
  final int used;
  final int limit;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shown = used > limit ? limit : used;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
            Text(
              '$shown of $limit',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadii.pill),
          child: LinearProgressIndicator(
            value: limit == 0 ? 1 : shown / limit,
            minHeight: 6,
            color: color,
            backgroundColor: color.withValues(alpha: 0.12),
          ),
        ),
      ],
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    super.key,
    required this.plan,
    required this.price,
    required this.period,
    required this.saving,
    required this.current,
    required this.currentPeriod,
    required this.busy,
    required this.enabled,
    required this.onPressed,
  });

  final SubscriptionPlan plan;
  final String price;
  final BillingPeriod period;

  /// Yearly only: what it saves over paying monthly.
  final String? saving;
  final SubscriptionPlan current;
  final BillingPeriod currentPeriod;
  final bool busy;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final samePlan = plan == current;
    final isCurrent = samePlan && period == currentPeriod;
    final label = isCurrent
        ? 'Current plan'
        : samePlan
        ? 'Switch to ${period.label.toLowerCase()}'
        : plan.isHigherThan(current)
        ? (current.isPaid ? 'Upgrade' : 'Subscribe')
        : 'Switch to ${plan.title}';

    return AppCard(
      color: isCurrent ? scheme.primary.withValues(alpha: 0.08) : null,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text(plan.title, style: theme.textTheme.titleMedium),
              ),
              Text(price, style: theme.textTheme.titleLarge),
              Text(
                ' / ${period.unit}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          if (saving != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                'Save $saving a year',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: AppColors.income,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          _LimitRow(
            icon: Icons.receipt_long_rounded,
            color: AppColors.primary,
            text: '${_count(plan.monthlyLimit)} transactions a month',
          ),
          const SizedBox(height: AppSpacing.xs),
          _LimitRow(
            icon: Icons.swap_vert_rounded,
            color: scheme.onSurfaceVariant,
            text: 'Income or expense, in any mix',
          ),
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            width: double.infinity,
            child: isCurrent
                ? OutlinedButton(onPressed: null, child: Text(label))
                : FilledButton(
                    onPressed: enabled ? onPressed : null,
                    child: busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(label),
                  ),
          ),
        ],
      ),
    );
  }
}

class _LimitRow extends StatelessWidget {
  const _LimitRow({
    required this.icon,
    required this.color,
    required this.text,
  });

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
        ),
      ],
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AppCard(
      color: AppColors.warning.withValues(alpha: 0.08),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.warning),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              text,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: scheme.onSurface),
            ),
          ),
        ],
      ),
    );
  }
}
