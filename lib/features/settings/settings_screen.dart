import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:flutter_easyloading/flutter_easyloading.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/avatar_provider.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/utils/snackbar_helper.dart';
import '../../core/utils/backup_service.dart';
import '../../core/utils/user_facing_error.dart';
import '../../providers/auth_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/contribution_provider.dart';
import '../../widgets/app_logo.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Currencies the app can display, with the symbol shown in the picker.
const _currencies = <String, String>{
  'INR': 'Indian Rupee',
  'USD': 'US Dollar',
  'EUR': 'Euro',
  'GBP': 'British Pound',
};

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
              child: Text('Currency', style: Theme.of(ctx).textTheme.titleLarge),
            ),
            for (final entry in _currencies.entries)
              _ChoiceTile(
                leadingText: CurrencyFormatter.symbolFor(entry.key),
                title: entry.value,
                subtitle: entry.key,
                selected: entry.key == current,
                onTap: () => Navigator.pop(ctx, entry.key),
              ),
            const SizedBox(height: AppSpacing.md),
          ],
        ),
      ),
    );
    if (picked != null) {
      ref.read(settingsProvider.notifier).setCurrency(picked);
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
    final isContributor = profile?.isContributor ?? false;
    final settings = ref.watch(settingsProvider);
    // Resolved the same way as the dashboard greeting so one name is shown
    // for the user everywhere in the app.
    final name = profile?.displayName?.trim().isNotEmpty == true
        ? profile!.displayName!
        : (user?.displayName?.trim().isNotEmpty == true
            ? user!.displayName!
            : (user?.email ?? 'Signed in user'));
    final photoUrl = profile?.photoUrl ?? user?.photoURL;
    final initial = name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : '?';
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
            initial: initial,
            photoUrl: photoUrl,
            isContributor: isContributor,
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
                icon: Icons.payments_outlined,
                title: 'Currency',
                subtitle:
                    '${_currencies[settings.currency] ?? settings.currency} · ${CurrencyFormatter.symbolFor(settings.currency)}',
                onTap: () => _pickCurrency(context, ref, settings.currency),
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
          const SectionLabel('About & support'),
          _SettingsGroup(
            children: [
              _SettingsTile(
                icon: Icons.favorite_rounded,
                title: 'Support Accounts Note',
                subtitle: isContributor
                    ? 'Thank you for your support'
                    : 'Donations & sponsorships',
                onTap: () => context.push('/contribute'),
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
          const SectionLabel('Account'),
          _SettingsGroup(
            children: [
              _SettingsTile(
                icon: Icons.logout_rounded,
                title: 'Log out',
                subtitle: 'Sign out on this device',
                onTap: () => _confirmSignOut(context, actions),
              ),
              _SettingsTile(
                icon: Icons.delete_forever_rounded,
                title: 'Delete account',
                subtitle: 'Removes all financial data',
                destructive: true,
                onTap: () => _confirmDelete(context, actions),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxl),
          const _VersionFooter(),
        ],
      ),
    );
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

  Future<void> _confirmDelete(
    BuildContext context,
    AuthActionsNotifier actions,
  ) async {
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => const _DeleteAccountDialog(),
    );

    if (action == 'backup_delete' || action == 'delete') {
      if (action == 'backup_delete') {
        EasyLoading.show(status: 'Backing up to Downloads...');
        try {
          final path = await BackupService.backupTransactionsToExcel();
          if (path != null) {
            EasyLoading.showSuccess('Saved to Downloads!');
            await Future.delayed(const Duration(seconds: 2));
          }
        } catch (e) {
          EasyLoading.showError('Backup failed, continuing delete...');
          await Future.delayed(const Duration(seconds: 2));
        }
      }

      EasyLoading.show(status: 'Confirming identity...');
      final result = await actions.deleteAccount();
      result.when(
        success: (_) {
          EasyLoading.showSuccess('Account and cloud data deleted');
        },
        failure: (f) {
          if (context.mounted) {
            EasyLoading.dismiss();
            SnackbarHelper.showError(context, f.userMessage);
          } else {
            EasyLoading.showError(f.userMessage);
          }
        },
      );
    }
  }
}

class _ProfileCard extends StatelessWidget {
  final String name;
  final String? email;
  final String initial;
  final String? photoUrl;
  final bool isContributor;
  final bool saving;
  final VoidCallback? onEditName;
  final VoidCallback? onChangePhoto;

  const _ProfileCard({
    required this.name,
    required this.email,
    required this.initial,
    required this.photoUrl,
    required this.isContributor,
    required this.saving,
    required this.onEditName,
    required this.onChangePhoto,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasPhoto = photoUrl != null && photoUrl!.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.brandDeep, AppColors.brand],
        ),
        borderRadius: BorderRadius.circular(AppRadii.hero),
        boxShadow: [
          BoxShadow(
            color: AppColors.brand.withValues(alpha: 0.22),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onChangePhoto,
                  customBorder: const CircleBorder(),
                  child: CircleAvatar(
                    radius: 32,
                    backgroundColor: Colors.white.withValues(alpha: 0.2),
                    backgroundImage: getAvatarProvider(photoUrl),
                    child: hasPhoto
                        ? null
                        : Text(
                            initial,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 24,
                            ),
                          ),
                  ),
                ),
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: Material(
                  color: Colors.white,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: onChangePhoto,
                    child: const Padding(
                      padding: EdgeInsets.all(5),
                      child: Icon(
                        Icons.camera_alt_rounded,
                        size: 14,
                        color: AppColors.brandDeep,
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
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (email != null)
                  Text(
                    email!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.white.withValues(alpha: 0.85),
                    ),
                  ),
                if (isContributor) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(AppRadii.pill),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.favorite_rounded,
                            size: 12, color: Colors.white),
                        const SizedBox(width: 5),
                        Text(
                          'Contributor',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: Colors.white,
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
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: const Text('Edit name'),
                ),
              ],
            ),
          ),
          if (saving)
            const Padding(
              padding: EdgeInsets.only(left: AppSpacing.sm),
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
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
  final bool destructive;

  const _SettingsTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accent = destructive ? scheme.error : scheme.primary;

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
          color: destructive ? scheme.error : scheme.onSurface,
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

class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog();

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  int _secondsLeft = 10;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsLeft > 0) {
        setState(() => _secondsLeft--);
      } else {
        _timer?.cancel();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return AlertDialog(
      icon: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: scheme.error.withValues(alpha: 0.1),
          shape: BoxShape.circle,
        ),
        child: Icon(Icons.warning_amber_rounded, color: scheme.error, size: 26),
      ),
      title: const Text('Delete your account?'),
      content: const Text(
        'This permanently deletes your profile, transactions, budgets, and categories. This cannot be undone.\n\nYou will be asked to confirm with Google (or Apple) before deletion.\n\nYou can download a backup of your transactions in Excel format before deleting.',
      ),
      actions: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            FilledButton.icon(
              icon: const Icon(Icons.download_rounded, size: 18),
              onPressed: _secondsLeft > 0
                  ? null
                  : () => Navigator.pop(context, 'backup_delete'),
              label: Text(
                _secondsLeft > 0
                    ? 'Backup & Delete ($_secondsLeft)'
                    : 'Backup & Delete',
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: scheme.error),
              onPressed:
                  _secondsLeft > 0 ? null : () => Navigator.pop(context, 'delete'),
              child: const Text('Delete without backup'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ],
    );
  }
}
