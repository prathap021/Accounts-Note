import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/user_facing_error.dart';
import '../../providers/auth_provider.dart';
import '../../providers/contribution_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  Future<void> _openUrl(BuildContext context, String url) async {
    final uri = Uri.parse(url);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userFacingError())),
      );
    }
  }

  Future<void> _editName(
    BuildContext context,
    WidgetRef ref,
    String current,
  ) async {
    final controller = TextEditingController(text: current);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit name'),
        content: TextField(
          controller: controller,
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
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty || !context.mounted) return;

    final result =
        await ref.read(authActionsProvider.notifier).updateDisplayName(name);
    if (!context.mounted) return;
    result.when(
      success: (_) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Name updated')),
        );
      },
      failure: (f) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(f.userMessage)),
        );
      },
    );
  }

  Future<void> _changePhoto(BuildContext context, WidgetRef ref) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
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
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (source == null || !context.mounted) return;

    final picked = await ImagePicker().pickImage(
      source: source,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );
    if (picked == null || !context.mounted) return;

    final result = await ref
        .read(authActionsProvider.notifier)
        .updateProfilePhoto(File(picked.path));
    if (!context.mounted) return;
    result.when(
      success: (_) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile photo updated')),
        );
      },
      failure: (f) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(f.userMessage)),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authStateProvider).asData?.value;
    final profile = ref.watch(userProfileProvider).asData?.value;
    final actionState = ref.watch(authActionsProvider);
    final actions = ref.read(authActionsProvider.notifier);
    final isContributor = profile?.isContributor ?? false;
    final scheme = Theme.of(context).colorScheme;
    final name = user?.displayName?.trim().isNotEmpty == true
        ? user!.displayName!
        : (profile?.displayName?.trim().isNotEmpty == true
            ? profile!.displayName!
            : (user?.email ?? 'Signed in user'));
    final photoUrl = user?.photoURL ?? profile?.photoUrl;
    final initial = name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : '?';
    final saving = actionState.isLoading;

    return Scaffold(
      appBar: AppBar(
        title: const Text('You'),
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
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        children: [
          Text(
            'Profile & settings',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.brandDeep, AppColors.brand],
              ),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Row(
              children: [
                Stack(
                  children: [
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: saving ? null : () => _changePhoto(context, ref),
                        customBorder: const CircleBorder(),
                        child: CircleAvatar(
                          radius: 32,
                          backgroundColor: Colors.white.withValues(alpha: 0.2),
                          backgroundImage:
                              photoUrl != null && photoUrl.isNotEmpty
                                  ? NetworkImage(photoUrl)
                                  : null,
                          child: photoUrl != null && photoUrl.isNotEmpty
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
                          onTap:
                              saving ? null : () => _changePhoto(context, ref),
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
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                ),
                      ),
                      if (user?.email != null)
                        Text(
                          user!.email!,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Colors.white.withValues(alpha: 0.8),
                                  ),
                        ),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: saving
                            ? null
                            : () => _editName(context, ref, name),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
                        ),
                        icon: const Icon(Icons.edit_outlined, size: 16),
                        label: const Text('Edit name'),
                      ),
                    ],
                  ),
                ),
                if (saving)
                  const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _SettingsGroup(
            children: [
              _SettingsTile(
                icon: Icons.person_outline_rounded,
                title: 'Edit profile photo',
                subtitle: 'Camera or gallery',
                onTap: saving ? null : () => _changePhoto(context, ref),
              ),
              _SettingsTile(
                icon: Icons.badge_outlined,
                title: 'Edit display name',
                subtitle: name,
                onTap: saving ? null : () => _editName(context, ref, name),
              ),
              _SettingsTile(
                icon: Icons.favorite_rounded,
                title: 'Support Accounts Note',
                subtitle: isContributor
                    ? 'Thank you for your support'
                    : 'Optional donations & sponsorships',
                onTap: () => context.push('/contribute'),
              ),
              _SettingsTile(
                icon: Icons.category_outlined,
                title: 'Manage categories',
                onTap: () => context.push('/categories'),
              ),
              const _SettingsTile(
                icon: Icons.currency_rupee_rounded,
                title: 'Currency',
                subtitle: 'INR (₹)',
              ),
              const _SettingsTile(
                icon: Icons.dark_mode_outlined,
                title: 'Theme',
                subtitle: 'Follows system',
              ),
              const _SettingsTile(
                icon: Icons.notifications_none_rounded,
                title: 'Notifications',
                subtitle: 'Budget alerts & summaries',
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            'Open source',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Accounts Note is free and open source. View the code, report issues, '
            'or contribute on GitHub.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.35,
                ),
          ),
          const SizedBox(height: 12),
          _SettingsGroup(
            children: [
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
                onTap: () => _openUrl(
                  context,
                  '${AppLinks.githubRepo}/issues',
                ),
              ),
              const _SettingsTile(
                icon: Icons.balance_outlined,
                title: 'License',
                subtitle: '${AppLinks.license} · Free to use, fork, and share',
              ),
            ],
          ),
          const SizedBox(height: 14),
          _SettingsGroup(
            children: [
              _SettingsTile(
                icon: Icons.logout_rounded,
                title: 'Log out',
                onTap: () => actions.signOut(),
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
          const SizedBox(height: 24),
          Text(
            'Accounts Note · Open source · ${AppLinks.license}',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 6),
          InkWell(
            onTap: () => _openUrl(context, AppLinks.githubRepo),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Text(
                AppLinks.githubRepo.replaceFirst('https://', ''),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w600,
                      decoration: TextDecoration.underline,
                      decorationColor: scheme.primary.withValues(alpha: 0.4),
                    ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    AuthActionsNotifier actions,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => const _DeleteAccountDialog(),
    );
    if (confirmed == true) {
      await actions.deleteAccount();
    }
  }
}

class _SettingsGroup extends StatelessWidget {
  final List<Widget> children;
  const _SettingsGroup({required this.children});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(
          color: scheme.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            children[i],
            if (i != children.length - 1)
              Divider(
                height: 1,
                indent: 56,
                color: scheme.outlineVariant.withValues(alpha: 0.35),
              ),
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
    final scheme = Theme.of(context).colorScheme;
    final color = destructive ? scheme.error : scheme.onSurface;

    return ListTile(
      onTap: onTap,
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: (destructive ? scheme.error : scheme.primary)
              .withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          icon,
          size: 20,
          color: destructive ? scheme.error : scheme.primary,
        ),
      ),
      title: Text(
        title,
        style: TextStyle(color: color, fontWeight: FontWeight.w600),
      ),
      subtitle: subtitle == null
          ? null
          : Text(subtitle!, style: TextStyle(color: scheme.onSurfaceVariant)),
      trailing: onTap == null
          ? null
          : Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
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
    return AlertDialog(
      title: const Text('Delete your account?'),
      content: const Text(
        'This permanently deletes your profile, transactions, budgets, and categories. This cannot be undone.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
          onPressed:
              _secondsLeft > 0 ? null : () => Navigator.pop(context, true),
          child: Text(
            _secondsLeft > 0
                ? 'Delete everything ($_secondsLeft)'
                : 'Delete everything',
          ),
        ),
      ],
    );
  }
}
