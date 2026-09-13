import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/result.dart';
import '../../providers/contribution_provider.dart';

class ContributeScreen extends ConsumerStatefulWidget {
  const ContributeScreen({super.key});

  @override
  ConsumerState<ContributeScreen> createState() => _ContributeScreenState();
}

class _ContributeScreenState extends ConsumerState<ContributeScreen> {
  double? _selectedPreset = ContributionPricing.presetUsd.first;
  final _customController = TextEditingController();
  bool _useCustom = false;

  @override
  void dispose() {
    _customController.dispose();
    super.dispose();
  }

  double? get _amount {
    if (_useCustom) {
      return double.tryParse(_customController.text.trim());
    }
    return _selectedPreset;
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(userProfileProvider).asData?.value;
    final entitlement = ref.watch(transactionEntitlementProvider);
    final actionState = ref.watch(contributionActionsProvider);
    final actions = ref.read(contributionActionsProvider.notifier);
    final scheme = Theme.of(context).colorScheme;
    final unlocked = profile?.isUnlocked ?? false;

    ref.listen(contributionActionsProvider, (prev, next) {
      if (next is AsyncError) {
        final err = next.error;
        final message =
            err is AppFailure ? err.message : 'Something went wrong.';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Contribute'),
        leading: IconButton(
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
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.brandDeep, AppColors.brand, Color(0xFF14B8A6)],
              ),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  unlocked ? 'Thank you!' : 'Support Accounts Note',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  unlocked
                      ? 'Thank you for supporting Accounts Note. Unlimited entries stay unlocked.'
                      : 'Contribution is optional. Everyone gets '
                          '${AppDefaults.freeDailyTransactionLimit} free income & expense '
                          'entries per day. A gift of \$${ContributionPricing.minUsd.toStringAsFixed(0)}+ '
                          'removes the daily limit if you want.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.white.withValues(alpha: 0.9),
                      ),
                ),
                if (!unlocked) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Today: ${entitlement.usedToday}/${entitlement.dailyLimit} free entries used',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ],
                if (unlocked && profile?.lastContributionAt != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Last gift: \$${profile!.totalContributedUsd.toStringAsFixed(2)} · '
                    '${DateFormat.yMMMd().format(profile.lastContributionAt!)}',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: Colors.white.withValues(alpha: 0.9),
                        ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Choose an amount (USD)',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            'Minimum \$${ContributionPricing.minUsd.toStringAsFixed(0)}. Payments via Stripe.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              for (final preset in ContributionPricing.presetUsd) ...[
                Expanded(
                  child: _AmountChip(
                    label: '\$${preset.toStringAsFixed(0)}',
                    selected: !_useCustom && _selectedPreset == preset,
                    onTap: () => setState(() {
                      _useCustom = false;
                      _selectedPreset = preset;
                      _customController.clear();
                    }),
                  ),
                ),
                if (preset != ContributionPricing.presetUsd.last)
                  const SizedBox(width: 10),
              ],
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Or enter your own amount',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _customController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
            decoration: InputDecoration(
              prefixText: '\$ ',
              labelText: 'Custom amount',
              hintText: 'e.g. 15',
              helperText:
                  'Minimum \$${ContributionPricing.minUsd.toStringAsFixed(0)}',
              filled: true,
            ),
            onTap: () => setState(() => _useCustom = true),
            onChanged: (_) => setState(() => _useCustom = true),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: actionState.isLoading
                ? null
                : () {
                    final amount = _amount;
                    if (amount == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Enter a valid contribution amount.'),
                        ),
                      );
                      return;
                    }
                    actions.contribute(amount);
                  },
            icon: actionState.isLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.favorite_rounded),
            label: Text(
              unlocked ? 'Contribute again' : 'Contribute (optional)',
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'You can keep using the free daily entries without contributing.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 28),
          Text(
            'Why contribute?',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 8),
          const _Benefit(text: 'Optional thank-you that removes the daily free limit'),
          const _Benefit(text: 'Supports ongoing development'),
          const _Benefit(text: 'One-time payment — no subscription'),
        ],
      ),
    );
  }
}

class _AmountChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _AmountChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected
          ? scheme.primary.withValues(alpha: 0.12)
          : scheme.surfaceContainer,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected
                  ? scheme.primary
                  : scheme.outlineVariant.withValues(alpha: 0.4),
              width: selected ? 1.5 : 1,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: selected ? scheme.primary : scheme.onSurface,
                ),
          ),
        ),
      ),
    );
  }
}

class _Benefit extends StatelessWidget {
  final String text;
  const _Benefit({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          const Icon(Icons.check_circle_rounded,
              color: AppColors.income, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
