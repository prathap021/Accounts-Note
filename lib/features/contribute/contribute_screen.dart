import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/result.dart';
import '../../core/utils/snackbar_helper.dart';
import '../../core/utils/user_facing_error.dart';
import '../../providers/contribution_provider.dart';
import 'contribution_dialogs.dart';

enum _SupportKind { oneTime, recurring, sponsor }

class ContributeScreen extends ConsumerStatefulWidget {
  const ContributeScreen({super.key});

  @override
  ConsumerState<ContributeScreen> createState() => _ContributeScreenState();
}

class _ContributeScreenState extends ConsumerState<ContributeScreen> {
  _SupportKind? _selectedKind;
  double? _selectedPreset = ContributionPricing.presetUsd.first;
  final _customController = TextEditingController();
  final _featureController = TextEditingController();
  bool _useCustom = false;
  bool _thankYouShown = false;

  @override
  void dispose() {
    _customController.dispose();
    _featureController.dispose();
    super.dispose();
  }

  double? get _amount {
    if (_useCustom) {
      return double.tryParse(_customController.text.trim());
    }
    return _selectedPreset;
  }

  String get _continueLabel {
    switch (_selectedKind) {
      case _SupportKind.oneTime:
        return 'Continue with one-time donation';
      case _SupportKind.recurring:
        return 'Continue with monthly support';
      case _SupportKind.sponsor:
        return 'Continue to sponsor a feature';
      case null:
        return 'Choose a support option';
    }
  }

  void _showThankYouOnce() {
    if (_thankYouShown || !mounted) return;
    _thankYouShown = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showContributionThankYouDialog(context);
    });
  }

  Future<void> _startCheckout() async {
    final kind = _selectedKind;
    if (kind == null) return;

    final amount = _amount;
    if (amount == null) {
      SnackbarHelper.showError(context, 'Enter a valid amount.');
      return;
    }

    final featureNote = _featureController.text.trim();
    if (kind == _SupportKind.sponsor && featureNote.isEmpty) {
      SnackbarHelper.showError(context, 'Describe the feature you\'d like to sponsor.');
      return;
    }

    await ref.read(contributionActionsProvider.notifier).contribute(
          amount,
          supportType: switch (kind) {
            _SupportKind.oneTime => 'one_time',
            _SupportKind.recurring => 'recurring',
            _SupportKind.sponsor => 'sponsor',
          },
          featureNote: kind == _SupportKind.sponsor ? featureNote : null,
        );
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(userProfileProvider).asData?.value;
    final actionState = ref.watch(contributionActionsProvider);
    final scheme = Theme.of(context).colorScheme;
    final isContributor = profile?.isContributor ?? false;

    ref.listen(contributionActionsProvider, (prev, next) {
      if (next is AsyncError) {
        final err = next.error;
        final message =
            err is AppFailure ? err.userMessage : userFacingError(err);
        SnackbarHelper.showError(context, message);
      }
    });

    ref.listen(userProfileProvider, (prev, next) {
      final wasThisMonth =
          prev?.asData?.value?.contributedInCurrentMonth() ?? false;
      final nowThisMonth =
          next.asData?.value?.contributedInCurrentMonth() ?? false;
      if (!wasThisMonth && nowThisMonth) {
        _showThankYouOnce();
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Support'),
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
                  'Support Accounts Note',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Financial contributions',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Accounts Note is a free, open-source Flutter app for managing '
                  'your accounts and notes. It\'s built and maintained in spare '
                  'time, with no ads or paid features.\n\n'
                  'If this app helps you and you\'d like to support its ongoing '
                  'development, you can contribute financially.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.white.withValues(alpha: 0.92),
                        height: 1.4,
                      ),
                ),
                if (isContributor && profile?.lastContributionAt != null) ...[
                  const SizedBox(height: 14),
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
          const SizedBox(height: 22),
          Text(
            'Ways to support',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 10),
          _SupportOptionCard(
            emoji: '☕',
            title: 'One-time donation',
            subtitle:
                'Helps cover hosting, domains, and development time.',
            selected: _selectedKind == _SupportKind.oneTime,
            onTap: () => setState(() => _selectedKind = _SupportKind.oneTime),
          ),
          const SizedBox(height: 10),
          _SupportOptionCard(
            emoji: '🔄',
            title: 'Recurring support',
            subtitle:
                'Makes long-term maintenance and new features more sustainable.',
            selected: _selectedKind == _SupportKind.recurring,
            onTap: () => setState(() => _selectedKind = _SupportKind.recurring),
          ),
          const SizedBox(height: 10),
          _SupportOptionCard(
            emoji: '💼',
            title: 'Sponsor a feature',
            subtitle:
                'Fund a specific improvement (e.g. better export, cloud sync, advanced filters).',
            selected: _selectedKind == _SupportKind.sponsor,
            onTap: () => setState(() => _selectedKind = _SupportKind.sponsor),
          ),
          if (_selectedKind != null) ...[
            const SizedBox(height: 24),
            Text(
              _selectedKind == _SupportKind.recurring
                  ? 'Monthly amount (USD)'
                  : 'Amount (USD)',
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
                      label: _selectedKind == _SupportKind.recurring
                          ? '\$${preset.toStringAsFixed(0)}/mo'
                          : '\$${preset.toStringAsFixed(0)}',
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
            TextField(
              controller: _customController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              decoration: InputDecoration(
                prefixText: '\$ ',
                labelText: _selectedKind == _SupportKind.recurring
                    ? 'Custom monthly amount'
                    : 'Custom amount',
                hintText: 'e.g. 15',
                helperText:
                    'Minimum \$${ContributionPricing.minUsd.toStringAsFixed(0)}',
                filled: true,
              ),
              onTap: () => setState(() => _useCustom = true),
              onChanged: (_) => setState(() => _useCustom = true),
            ),
            if (_selectedKind == _SupportKind.sponsor) ...[
              const SizedBox(height: 16),
              TextField(
                controller: _featureController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Feature to sponsor',
                  hintText: 'e.g. CSV export, advanced filters, cloud sync…',
                  filled: true,
                ),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: actionState.isLoading ? null : _startCheckout,
              child: actionState.isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(_continueLabel),
            ),
          ],
          const SizedBox(height: 16),
          Text(
            'Support is completely optional. Accounts Note stays free, with no ads '
            'and no paid locks on income or expense tracking.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}

class _SupportOptionCard extends StatelessWidget {
  final String emoji;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _SupportOptionCard({
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected
          ? scheme.primary.withValues(alpha: 0.1)
          : scheme.surfaceContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: selected
              ? scheme.primary
              : scheme.outlineVariant.withValues(alpha: 0.4),
          width: selected ? 1.5 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(emoji, style: const TextStyle(fontSize: 22)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: selected ? scheme.primary : scheme.onSurface,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            height: 1.35,
                          ),
                    ),
                  ],
                ),
              ),
              if (selected)
                Icon(Icons.check_circle_rounded, color: scheme.primary),
            ],
          ),
        ),
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
          padding: const EdgeInsets.symmetric(vertical: 14),
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
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: selected ? scheme.primary : scheme.onSurface,
                ),
          ),
        ),
      ),
    );
  }
}
