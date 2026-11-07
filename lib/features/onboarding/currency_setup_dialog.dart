import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/currencies.dart';
import '../../core/services/country_locator.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/settings_provider.dart';

/// First-run currency choice: offer to read the country from the phone's
/// location, and otherwise keep the currency of the phone's region.
///
/// Asked once, at the end of the intro. The answer only sets a default; the
/// currency can be changed at any time in Settings.
Future<void> chooseStartingCurrency(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  final chosen = await showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _CurrencySetupDialog(),
  );
  if (chosen == null) return;
  await ref.read(settingsProvider.notifier).setCurrency(chosen);
  final c = currencyByCode(chosen);
  messenger.showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      content: Text(
        'Currency set to ${c?.name ?? chosen} (${c?.symbol.trim() ?? chosen}). '
        'Change it any time in Settings.',
      ),
    ),
  );
}

class _CurrencySetupDialog extends ConsumerStatefulWidget {
  const _CurrencySetupDialog();

  @override
  ConsumerState<_CurrencySetupDialog> createState() =>
      _CurrencySetupDialogState();
}

class _CurrencySetupDialogState extends ConsumerState<_CurrencySetupDialog> {
  bool _locating = false;
  bool _notFound = false;

  Future<void> _useLocation() async {
    setState(() {
      _locating = true;
      _notFound = false;
    });
    final country = await ref
        .read(countryLocatorProvider)
        .countryFromLocation();
    if (!mounted) return;
    if (country == null) {
      setState(() {
        _locating = false;
        _notFound = true;
      });
      return;
    }
    Navigator.pop(context, currencyForCountry(country));
  }

  @override
  Widget build(BuildContext context) {
    final current = ref.watch(settingsProvider).currency;
    final c = currencyByCode(current);
    final label = '${c?.name ?? current} (${c?.symbol.trim() ?? current})';
    final theme = Theme.of(context);

    return AlertDialog(
      icon: const Icon(Icons.public_rounded, color: AppColors.primary),
      title: const Text('Set your currency'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Accounts Note can use your approximate location once to pick '
            "the currency you keep accounts in. It stays on your phone: "
            "it isn't saved or sent anywhere.",
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            _notFound
                ? "Couldn't find your location. Keeping $label, from your "
                      "phone's region."
                : "Without it, you'll start with $label, from your phone's "
                      'region.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (_locating) ...[
            const SizedBox(height: AppSpacing.lg),
            const Row(
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: AppSpacing.md),
                Text('Finding your country…'),
              ],
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _locating ? null : () => Navigator.pop(context, null),
          child: Text(_notFound ? 'Continue' : 'Not now'),
        ),
        if (!_notFound)
          FilledButton(
            onPressed: _locating ? null : _useLocation,
            child: const Text('Use my location'),
          ),
      ],
    );
  }
}
