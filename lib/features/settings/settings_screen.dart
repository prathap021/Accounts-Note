import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';


import '../../core/constants/app_constants.dart';
import '../../core/constants/currencies.dart';
import '../../core/services/app_review_service.dart';
import '../../core/services/app_update_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/responsive.dart';
import '../../core/utils/greeting.dart';
import '../../widgets/user_avatar.dart';
import '../lock/pin_setup_sheet.dart';
import 'backup_flow.dart';
import 'clear_data_flow.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/utils/snackbar_helper.dart';
import '../../core/utils/user_facing_error.dart';
import '../../providers/account_provider.dart';
import '../../providers/app_lock_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/automation_provider.dart';
import '../../providers/credit_card_provider.dart';
import '../../providers/settings_provider.dart';
import '../../models/subscription_plan.dart';
import '../../providers/profile_provider.dart';
import '../../providers/subscription_provider.dart';
import '../../widgets/app_logo.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Currencies the app can display, with the symbol shown in the picker.

String _ordinal(int n) {
  if (n >= 11 && n <= 13) return '${n}th';
  return switch (n % 10) {
    1 => '${n}st',
    2 => '${n}nd',
    3 => '${n}rd',
    _ => '${n}th',
  };
}

String _themeLabel(ThemeMode mode) => switch (mode) {
      ThemeMode.system => 'Follows system',
      ThemeMode.light => 'Light',
      ThemeMode.dark => 'Dark',
    };

IconData _themeIcon(ThemeMode mode) => switch (mode) {
      ThemeMode.system => Icons.brightness_auto_rounded,
      ThemeMode.light => Icons.light_mode_rounded,
      ThemeMode.dark => Icons.dark_mode_rounded,
    };

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  Future<void> _openUrl(BuildContext context, String url) async {
    final uri = Uri.parse(url);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      SnackbarHelper.showError(context, userFacingError());
    }
  }

  Future<void> _editName(
    BuildContext context,
    WidgetRef ref,
    String current,
  ) async {
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => _EditNameDialog(currentName: current),
    );
    if (name == null || name.isEmpty || !context.mounted) return;

    final result =
        await ref.read(authActionsProvider.notifier).updateDisplayName(name);
    if (!context.mounted) return;
    result.when(
      success: (_) {
        SnackbarHelper.showSuccess(context, 'Name updated');
      },
      failure: (f) {
        SnackbarHelper.showError(context, f.userMessage);
      },
    );
  }

  Future<void> _changePhoto(BuildContext context, WidgetRef ref) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                0,
                AppSpacing.xl,
                AppSpacing.md,
              ),
              child: Text(
                'Profile photo',
                style: Theme.of(ctx).textTheme.titleLarge,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
        ),
      ),
    );
    if (source == null || !context.mounted) return;

    final picked = await ImagePicker().pickImage(
      source: source,
      maxWidth: 256,
      maxHeight: 256,
      imageQuality: 70,
    );
    if (picked == null || !context.mounted) return;

    final result = await ref
        .read(authActionsProvider.notifier)
        .updateProfilePhoto(File(picked.path));
    if (!context.mounted) return;
    result.when(
      success: (_) {
        SnackbarHelper.showSuccess(context, 'Profile photo updated');
      },
      failure: (f) {
        SnackbarHelper.showError(context, f.userMessage);
      },
    );
  }

  Future<void> _pickCurrency(
    BuildContext context,
    WidgetRef ref,
    String current,
  ) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      // Every Play currency: the sheet grows to most of the screen and
      // scrolls, with a search box on top.
      isScrollControlled: true,
      builder: (ctx) => _CurrencyPickerSheet(
        current: current,
        local: currencyForCountry(ref.read(deviceCountryProvider)),
      ),
    );
    if (picked != null) {
      ref.read(settingsProvider.notifier).setCurrency(picked);
    }
  }

  Future<void> _pickMonthStart(
    BuildContext context,
    WidgetRef ref,
    int current,
  ) async {
    final picked = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            0,
            AppSpacing.xl,
            AppSpacing.xl,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Month starts on',
                style: Theme.of(ctx).textTheme.titleLarge,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Budgets, the dashboard and the Reports month run from this '
                'day to the day before it next month. Pick your pay day to '
                'follow your salary cycle.',
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
              const SizedBox(height: AppSpacing.lg),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  for (var d = 1; d <= 28; d++)
                    ChoiceChip(
                      label: Text('$d'),
                      selected: d == current,
                      onSelected: (_) => Navigator.pop(ctx, d),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (picked != null) {
      await ref.read(settingsProvider.notifier).setMonthStartDay(picked);
    }
  }

  Future<void> _pickTheme(
    BuildContext context,
    WidgetRef ref,
    ThemeMode current,
  ) async {
    final picked = await showModalBottomSheet<ThemeMode>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                0,
                AppSpacing.xl,
                AppSpacing.md,
              ),
              child: Text(
                'Appearance',
                style: Theme.of(ctx).textTheme.titleLarge,
              ),
            ),
            for (final mode in ThemeMode.values)
              _ChoiceTile(
                icon: _themeIcon(mode),
                title: _themeLabel(mode),
                selected: mode == current,
                onTap: () => Navigator.pop(ctx, mode),
              ),
            const SizedBox(height: AppSpacing.md),
          ],
        ),
      ),
    );
    if (picked != null) {
      ref.read(settingsProvider.notifier).setThemeMode(picked);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authStateProvider).asData?.value;
    final profile = ref.watch(userProfileProvider).asData?.value;
    final actionState = ref.watch(authActionsProvider);
    final actions = ref.read(authActionsProvider.notifier);
    final plan = ref.watch(currentPlanProvider);
    final settings = ref.watch(settingsProvider);
    final cardCount = ref.watch(creditCardLookupProvider).length;
    final accountCount = ref.watch(accountLookupProvider).length;
    // Resolved the same way as the dashboard greeting so one name is shown
    // for the user everywhere in the app.
    final name = resolveDisplayName(
      profileName: profile?.displayName,
      authName: user?.displayName,
      email: user?.email,
      fallback: 'Signed in user',
    );
    final photoUrl = profile?.photoUrl ?? user?.photoURL;
    final saving = actionState.isLoading;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile & settings'),
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
          _ProfileCard(
            name: name,
            email: user?.email,
            photoUrl: photoUrl,
            plan: plan,
            saving: saving,
            onEditName: saving ? null : () => _editName(context, ref, name),
            onChangePhoto: saving ? null : () => _changePhoto(context, ref),
          ),
          const SizedBox(height: AppSpacing.xxl),
          const SectionLabel('Preferences'),
          _SettingsGroup(
            children: [
              _SettingsTile(
                icon: Icons.category_outlined,
                title: 'Manage categories',
                subtitle: 'Income and expense categories',
                onTap: () => context.push('/categories'),
              ),
              _SettingsTile(
                icon: Icons.account_balance_outlined,
                title: 'Accounts',
                subtitle: switch (accountCount) {
                  0 => 'Cash, bank, UPI and wallets, and transfers',
                  1 => '1 account',
                  _ => '$accountCount accounts',
                },
                onTap: () => context.push('/accounts'),
              ),
              _SettingsTile(
                icon: Icons.credit_card_rounded,
                title: 'Credit cards',
                subtitle: switch (cardCount) {
                  0 => 'Add the cards you pay with',
                  1 => '1 card',
                  _ => '$cardCount cards',
                },
                onTap: () => context.push('/credit-cards'),
              ),
              _SettingsTile(
                icon: Icons.payments_outlined,
                title: 'Currency',
                subtitle:
                    '${currencyByCode(settings.currency)?.name ?? settings.currency} · ${CurrencyFormatter.symbolFor(settings.currency).trim()}',
                onTap: () => _pickCurrency(context, ref, settings.currency),
              ),
              _SettingsTile(
                icon: Icons.event_repeat_rounded,
                title: 'Month starts on',
                subtitle: settings.monthStartDay == 1
                    ? 'The 1st (calendar month)'
                    : 'The ${_ordinal(settings.monthStartDay)}, e.g. your pay day',
                onTap: () => _pickMonthStart(context, ref, settings.monthStartDay),
              ),
              _SettingsTile(
                icon: _themeIcon(settings.themeMode),
                title: 'Appearance',
                subtitle: _themeLabel(settings.themeMode),
                onTap: () => _pickTheme(context, ref, settings.themeMode),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          const SectionLabel('Subscription'),
          _SettingsGroup(
            children: [
              _SettingsTile(
                icon: Icons.workspace_premium_rounded,
                title: 'Subscription',
                subtitle: '${plan.title} · '
                    '${NumberFormat.decimalPattern().format(plan.monthlyLimit)} '
                    'transactions a month',
                onTap: () => context.push('/subscription'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          const SectionLabel('Automation'),
          _SettingsGroup(
            children: [
              _SettingsTile(
                icon: Icons.repeat_rounded,
                title: 'Recurring transactions',
                subtitle: 'Salary, rent, EMIs and subscriptions',
                onTap: () => context.push('/recurring'),
              ),
              const _NotificationToggles(),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          const SectionLabel('Backup'),
          _SettingsGroup(
            children: [
              _SettingsTile(
                icon: Icons.cloud_download_outlined,
                title: 'Back up now',
                subtitle:
                    'Save every transaction, category, card and budget to a file',
                onTap: () => runBackup(context, ref),
              ),
              _SettingsTile(
                icon: Icons.upload_file_rounded,
                title: 'Import a backup',
                subtitle:
                    'Add a backup to this account, e.g. from your other account',
                onTap: () => runImport(context, ref),
              ),
              _SettingsTile(
                icon: Icons.table_view_rounded,
                title: 'Import from CSV',
                subtitle: 'Entries from another app or a bank statement',
                onTap: () => runCsvImport(context, ref),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          const SectionLabel('About'),
          _SettingsGroup(
            children: [
              if (Platform.isAndroid || AppLinks.appStoreId != null)
                _SettingsTile(
                  icon: Icons.star_rate_rounded,
                  title: 'Rate Accounts Note',
                  subtitle: Platform.isIOS
                      ? 'Leave a review on the App Store'
                      : 'Leave a review on Google Play',
                  onTap: () =>
                      ref.read(appReviewServiceProvider).openStorePage(),
                ),
              if (ref.watch(inAppUpdateSupportedProvider))
                _SettingsTile(
                  icon: Icons.system_update_rounded,
                  title: 'Check for updates',
                  subtitle: switch (ref.watch(appUpdateControllerProvider).phase) {
                    UpdatePhase.checking => 'Checking…',
                    UpdatePhase.downloading => 'Downloading the update…',
                    UpdatePhase.readyToInstall => 'Update ready: tap to restart',
                    _ => 'Get the latest version from Google Play',
                  },
                  onTap: () => _checkForUpdates(context, ref),
                ),
              _SettingsTile(
                icon: Icons.privacy_tip_outlined,
                title: 'Privacy policy',
                subtitle: 'What the app stores, and where',
                onTap: () => _openUrl(context, AppLinks.privacyPolicy),
              ),
              _SettingsTile(
                icon: Icons.code_rounded,
                title: 'Source code',
                subtitle: 'github.com/prathap021/Accounts-Note',
                onTap: () => _openUrl(context, AppLinks.githubRepo),
              ),
              _SettingsTile(
                icon: Icons.bug_report_outlined,
                title: 'Report an issue',
                subtitle: 'Bugs, ideas, and feedback',
                onTap: () => _openUrl(context, '${AppLinks.githubRepo}/issues'),
              ),
              const _SettingsTile(
                icon: Icons.balance_outlined,
                title: 'License',
                subtitle: '${AppLinks.license} · Free to use, fork, and share',
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          const SectionLabel('Security'),
          const _SettingsGroup(children: [_SecurityToggles()]),
          const SizedBox(height: AppSpacing.xl),
          const SectionLabel('Account'),
          _SettingsGroup(
            children: [
              _SettingsTile(
                icon: Icons.delete_sweep_outlined,
                title: 'Clear all data',
                subtitle: 'Start over: removes every transaction, card and budget',
                onTap: () => runClearAllData(context, ref),
              ),
              _SettingsTile(
                icon: Icons.logout_rounded,
                title: 'Log out',
                subtitle: 'Sign out on this device',
                onTap: () => _confirmSignOut(context, actions),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxl),
          const _VersionFooter(),
        ],
      ),
    );
  }

  Future<void> _checkForUpdates(BuildContext context, WidgetRef ref) async {
    final updates = ref.read(appUpdateControllerProvider.notifier);
    if (ref.read(appUpdateControllerProvider).phase ==
        UpdatePhase.readyToInstall) {
      await updates.install();
      return;
    }
    await updates.checkNow();
    if (!context.mounted) return;
    final message = switch (ref.read(appUpdateControllerProvider).phase) {
      UpdatePhase.upToDate => "You're on the latest version.",
      UpdatePhase.downloading =>
        'Downloading the update. You can keep using the app.',
      UpdatePhase.readyToInstall => 'The update is ready to install.',
      UpdatePhase.unavailable =>
        'Updates are only available for the Google Play version of the app.',
      _ => null,
    };
    if (message != null) SnackbarHelper.showSuccess(context, message);
  }

  Future<void> _confirmSignOut(
    BuildContext context,
    AuthActionsNotifier actions,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text(
          'Your data stays safely synced — you can sign back in anytime.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Log out'),
          ),
        ],
      ),
    );
    if (confirmed == true) await actions.signOut();
  }
}

class _ProfileCard extends StatelessWidget {
  final String name;
  final String? email;
  final String? photoUrl;
  final SubscriptionPlan plan;
  final bool saving;
  final VoidCallback? onEditName;
  final VoidCallback? onChangePhoto;

  const _ProfileCard({
    required this.name,
    required this.email,
    required this.photoUrl,
    required this.plan,
    required this.saving,
    required this.onEditName,
    required this.onChangePhoto,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    // A light surface like every other card on the screen. Colour is spent on
    // the avatar ring and the plan badge, not a full slab, so the
    // user's name and address stay the loudest thing here.
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Stack(
            children: [
              Container(
                padding: EdgeInsets.all(3.rr),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  // Thin brand ring instead of a coloured background.
                  border: Border.all(
                    color: scheme.primary.withValues(alpha: 0.35),
                    width: 2,
                  ),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: onChangePhoto,
                    customBorder: const CircleBorder(),
                    child: UserAvatar(
                      radius: 30.rr,
                      photoUrl: photoUrl,
                      name: name,
                      email: email,
                      backgroundColor: scheme.primary.withValues(alpha: 0.12),
                      textStyle: theme.textTheme.headlineSmall?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: Material(
                  color: scheme.primary,
                  shape: CircleBorder(
                    side: BorderSide(color: scheme.surfaceContainer, width: 2),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: onChangePhoto,
                    child: Padding(
                      padding: EdgeInsets.all(5.rr),
                      child: Icon(
                        Icons.camera_alt_rounded,
                        size: 13.rr,
                        color: scheme.onPrimary,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium,
                ),
                if (email != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    email!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
                if (plan.isPaid) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.income.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(AppRadii.pill),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.workspace_premium_rounded,
                            size: 11.rr, color: AppColors.income),
                        const SizedBox(width: 5),
                        Text(
                          plan.title,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: AppColors.income,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.sm),
                TextButton.icon(
                  onPressed: onEditName,
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  icon: Icon(Icons.edit_outlined, size: 15.rr),
                  label: const Text('Edit name'),
                ),
              ],
            ),
          ),
          if (saving)
            Padding(
              padding: const EdgeInsets.only(left: AppSpacing.sm),
              child: SizedBox(
                width: 20.rr,
                height: 20.rr,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: scheme.primary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _VersionFooter extends StatelessWidget {
  const _VersionFooter();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox(height: 80);
        final info = snapshot.data!;
        return Column(
          children: [
            const AppLogo(size: 44, rounded: true),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Accounts Note',
              style: theme.textTheme.titleSmall?.copyWith(
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Version ${info.version} (${info.buildNumber})',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.xxl),
          ],
        );
      },
    );
  }
}

class _ChoiceTile extends StatelessWidget {
  final IconData? icon;
  final String? leadingText;
  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _ChoiceTile({
    this.icon,
    this.leadingText,
    required this.title,
    this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return ListTile(
      onTap: onTap,
      leading: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: (selected ? scheme.primary : scheme.onSurfaceVariant)
              .withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: icon != null
            ? Icon(
                icon,
                size: 19,
                color: selected ? scheme.primary : scheme.onSurfaceVariant,
              )
            : Text(
                leadingText ?? '',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: selected ? scheme.primary : scheme.onSurfaceVariant,
                ),
              ),
      ),
      title: Text(
        title,
        style: theme.textTheme.bodyLarge?.copyWith(
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: selected
          ? Icon(Icons.check_circle_rounded, color: scheme.primary)
          : null,
    );
  }
}

class _EditNameDialog extends StatefulWidget {
  final String currentName;
  const _EditNameDialog({required this.currentName});

  @override
  State<_EditNameDialog> createState() => _EditNameDialogState();
}

class _EditNameDialogState extends State<_EditNameDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.currentName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit name'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        maxLength: 60,
        decoration: const InputDecoration(
          labelText: 'Display name',
          hintText: 'Your name',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text.trim()),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _SettingsGroup extends StatelessWidget {
  final List<Widget> children;
  const _SettingsGroup({required this.children});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            children[i],
            if (i != children.length - 1)
              Divider(height: 1, indent: 68, color: scheme.outlineVariant),
          ],
        ],
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;

  const _SettingsTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accent = scheme.primary;

    return ListTile(
      onTap: onTap,
      shape: const RoundedRectangleBorder(),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xs,
      ),
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, size: 19, color: accent),
      ),
      title: Text(
        title,
        style: theme.textTheme.bodyLarge?.copyWith(
          color: scheme.onSurface,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: subtitle == null
          ? null
          : Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                subtitle!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
      trailing: onTap == null
          ? null
          : Icon(
              Icons.chevron_right_rounded,
              color: scheme.onSurfaceVariant,
              size: 20,
            ),
    );
  }
}

/// Every currency Google Play sells in. The phone's own currency and the
/// most used ones come first; the rest follow by name, with search.
class _CurrencyPickerSheet extends StatefulWidget {
  const _CurrencyPickerSheet({required this.current, required this.local});

  final String current;

  /// The currency of the phone's country.
  final String local;

  @override
  State<_CurrencyPickerSheet> createState() => _CurrencyPickerSheetState();
}

class _CurrencyPickerSheetState extends State<_CurrencyPickerSheet> {
  var _query = '';

  List<AppCurrency> get _suggested {
    final codes = <String>{widget.current, widget.local, ...kPopularCurrencyCodes};
    return [for (final code in codes) ?currencyByCode(code)];
  }

  List<AppCurrency> get _others {
    final suggested = _suggested.map((c) => c.code).toSet();
    return kCurrencies.where((c) => !suggested.contains(c.code)).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  bool _matches(AppCurrency c) {
    final q = _query.trim().toLowerCase();
    return q.isEmpty ||
        c.name.toLowerCase().contains(q) ||
        c.code.toLowerCase().contains(q);
  }

  Widget _tile(AppCurrency c) => _ChoiceTile(
        leadingText: c.symbol.trim(),
        title: c.name,
        subtitle: c.code,
        selected: c.code == widget.current,
        onTap: () => Navigator.pop(context, c.code),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final searching = _query.trim().isNotEmpty;
    final results = searching
        ? (kCurrencies.where(_matches).toList()
          ..sort((a, b) => a.name.compareTo(b.name)))
        : const <AppCurrency>[];

    Widget label(String text) => Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.md,
            AppSpacing.xl,
            AppSpacing.xs,
          ),
          child: Text(
            text,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        );

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.8,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xl,
                  0,
                  AppSpacing.xl,
                  AppSpacing.md,
                ),
                child: Text('Currency', style: theme.textTheme.titleLarge),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search_rounded),
                    hintText: 'Search currencies',
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              Expanded(
                child: ListView(
                  children: [
                    if (searching) ...[
                      for (final c in results) _tile(c),
                      if (results.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(AppSpacing.xl),
                          child: Text(
                            'No currency matches "${_query.trim()}".',
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                    ] else ...[
                      label('Suggested'),
                      for (final c in _suggested) _tile(c),
                      label('All currencies'),
                      for (final c in _others) _tile(c),
                    ],
                    const SizedBox(height: AppSpacing.md),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Daily reminder (with its time), budget alerts and bill reminders.
class _NotificationToggles extends ConsumerWidget {
  const _NotificationToggles();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(notificationSettingsProvider);
    final n = ref.read(notificationSettingsProvider.notifier);
    final time = s.reminderTime.format(context);

    Future<void> pickTime() async {
      final picked = await showTimePicker(
        context: context,
        initialTime: s.reminderTime,
        helpText: 'Remind me at',
      );
      if (picked != null) await n.setDailyReminder(true, at: picked);
    }

    return Column(
      children: [
        SwitchListTile(
          key: const Key('daily-reminder'),
          secondary: const Icon(Icons.notifications_active_outlined),
          title: const Text('Daily reminder'),
          subtitle: Text(
            s.dailyReminder
                ? 'Every day at $time. Tap to change the time.'
                : 'A nudge to add the day\'s expenses',
          ),
          value: s.dailyReminder,
          onChanged: (on) async {
            final ok = await n.setDailyReminder(on);
            if (on && !ok && context.mounted) {
              SnackbarHelper.showError(
                context,
                'Notifications are turned off for Accounts Note in your '
                'phone settings.',
              );
            }
          },
        ),
        if (s.dailyReminder)
          ListTile(
            leading: const SizedBox(width: 24),
            title: const Text('Reminder time'),
            trailing: Text(time),
            onTap: pickTime,
          ),
        SwitchListTile(
          secondary: const Icon(Icons.pie_chart_outline_rounded),
          title: const Text('Budget alerts'),
          subtitle: const Text('When spending reaches a budget\'s alert line and its limit'),
          value: s.budgetAlerts,
          onChanged: n.setBudgetAlerts,
        ),
        SwitchListTile(
          secondary: const Icon(Icons.event_note_outlined),
          title: const Text('Bill reminders'),
          subtitle: const Text('The day before a recurring expense is added'),
          value: s.billReminders,
          onChanged: n.setBillReminders,
        ),
      ],
    );
  }
}

/// App lock (PIN) and fingerprint unlock.
class _SecurityToggles extends ConsumerWidget {
  const _SecurityToggles();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lock = ref.watch(appLockProvider);
    final n = ref.read(appLockProvider.notifier);

    Future<void> toggleLock(bool on) async {
      if (on) {
        final pin = await askNewPin(context);
        if (pin == null) return;
        await n.setPin(pin);
        if (context.mounted) {
          SnackbarHelper.showSuccess(context, 'App lock is on.');
        }
      } else {
        final pin = await askPin(context, 'Enter your current PIN');
        if (pin == null) return;
        if (!n.checkPin(pin)) {
          if (context.mounted) SnackbarHelper.showError(context, 'Wrong PIN.');
          return;
        }
        await n.disable();
      }
    }

    return Column(
      children: [
        SwitchListTile(
          key: const Key('app-lock'),
          secondary: const Icon(Icons.lock_outline_rounded),
          title: const Text('App lock'),
          subtitle: Text(
            lock.enabled
                ? 'A PIN is asked for when the app opens'
                : 'Ask for a 4-digit PIN when the app opens',
          ),
          value: lock.enabled,
          onChanged: toggleLock,
        ),
        if (lock.enabled)
          SwitchListTile(
            key: const Key('biometric-unlock'),
            secondary: const Icon(Icons.fingerprint_rounded),
            title: const Text('Unlock with fingerprint'),
            subtitle: const Text('Or face, where the phone supports it'),
            value: lock.biometrics,
            onChanged: (on) async {
              final ok = await n.setBiometrics(on);
              if (on && !ok && context.mounted) {
                SnackbarHelper.showError(
                  context,
                  'Fingerprint unlock is not set up on this phone.',
                );
              }
            },
          ),
        if (lock.enabled)
          ListTile(
            leading: const SizedBox(width: 24),
            title: const Text('Change PIN'),
            onTap: () async {
              final current = await askPin(context, 'Enter your current PIN');
              if (current == null || !context.mounted) return;
              if (!n.checkPin(current)) {
                SnackbarHelper.showError(context, 'Wrong PIN.');
                return;
              }
              final pin = await askNewPin(context);
              if (pin == null) return;
              await n.setPin(pin);
              if (context.mounted) {
                SnackbarHelper.showSuccess(context, 'PIN changed.');
              }
            },
          ),
      ],
    );
  }
}

