import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../providers/auth_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authStateProvider).asData?.value;
    final actions = ref.read(authActionsProvider.notifier);
    final scheme = Theme.of(context).colorScheme;
    final name = user?.displayName ?? user?.email ?? 'Signed in user';
    final initial = name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : '?';

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
                CircleAvatar(
                  radius: 28,
                  backgroundColor: Colors.white.withValues(alpha: 0.2),
                  child: Text(
                    initial,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 22,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      if (user?.email != null)
                        Text(
                          user!.email!,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Colors.white.withValues(alpha: 0.8),
                              ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _SettingsGroup(
            children: [
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
            'Accounts Note · Open source · MIT',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(
      BuildContext context, AuthActionsNotifier actions) async {
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
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
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
        child: Icon(icon, size: 20, color: destructive ? scheme.error : scheme.primary),
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
