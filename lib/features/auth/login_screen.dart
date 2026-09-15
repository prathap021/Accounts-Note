import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/result.dart';
import '../../core/utils/snackbar_helper.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/app_logo.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _isSignUp = false;
  bool _showEmailForm = false;
  bool _obscure = true;

  /// Which auth button is busy: google | apple | email
  String? _busyAction;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _runAuth(String action, Future<void> Function() fn) async {
    if (_busyAction != null) return;
    setState(() => _busyAction = action);
    try {
      await fn();
    } finally {
      if (mounted) setState(() => _busyAction = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final actions = ref.read(authActionsProvider.notifier);
    final actionState = ref.watch(authActionsProvider);
    final isBusy = _busyAction != null || actionState.isLoading;

    ref.listen(authActionsProvider, (prev, next) {
      if (next is AsyncError) {
        final err = next.error;
        final message =
            err is AppFailure ? err.userMessage : 'Something went wrong. Please try again.';
        SnackbarHelper.showError(context, message);
      }
    });

    final isIOS = !kIsWeb && Platform.isIOS;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SoftMeshBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Center(
              child: SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: AppSpacing.xl),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: AppLogo(size: 76),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      Text(
                        'Accounts Note',
                        style:
                            Theme.of(context).textTheme.displaySmall?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -1.2,
                                  height: 1.05,
                                ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        'A calm, modern ledger for your income and expenses — synced wherever you go.',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              color: scheme.onSurfaceVariant,
                              height: 1.45,
                            ),
                      ),
                      const SizedBox(height: AppSpacing.xxl),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 280),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        child: _showEmailForm
                            ? _EmailForm(
                                key: const ValueKey('email'),
                                formKey: _formKey,
                                email: _email,
                                password: _password,
                                isSignUp: _isSignUp,
                                obscure: _obscure,
                                isLoading: isBusy,
                                onToggleObscure: () =>
                                    setState(() => _obscure = !_obscure),
                                onToggleMode: () =>
                                    setState(() => _isSignUp = !_isSignUp),
                                onBack: isBusy
                                    ? null
                                    : () =>
                                        setState(() => _showEmailForm = false),
                                onSubmit: () {
                                  if (!_formKey.currentState!.validate()) {
                                    return;
                                  }
                                  _runAuth('email', () async {
                                    if (_isSignUp) {
                                      await actions.signUpWithEmail(
                                        _email.text,
                                        _password.text,
                                      );
                                    } else {
                                      await actions.signInWithEmail(
                                        _email.text,
                                        _password.text,
                                      );
                                    }
                                  });
                                },
                              )
                            : _AuthOptions(
                                key: const ValueKey('options'),
                                isIOS: isIOS,
                                busyAction: _busyAction,
                                onGoogle: () => _runAuth(
                                      'google',
                                      actions.signInWithGoogle,
                                    ),
                                onApple: () => _runAuth(
                                      'apple',
                                      actions.signInWithApple,
                                    ),
                                onEmail: isBusy
                                    ? null
                                    : () => setState(
                                          () => _showEmailForm = true,
                                        ),
                              ),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      Text(
                        'Your data stays in your own account. No ads, no trackers.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AuthOptions extends StatelessWidget {
  final bool isIOS;
  final String? busyAction;
  final VoidCallback onGoogle;
  final VoidCallback onApple;
  final VoidCallback? onEmail;

  const _AuthOptions({
    super.key,
    required this.isIOS,
    required this.busyAction,
    required this.onGoogle,
    required this.onApple,
    required this.onEmail,
  });

  bool get _anyBusy => busyAction != null;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    Widget socialButton({
      required String action,
      required IconData icon,
      required double iconSize,
      required String label,
      required VoidCallback onPressed,
    }) {
      return FilledButton(
        onPressed: _anyBusy ? null : onPressed,
        child: busyAction == action
            ? SizedBox(
                height: 22,
                width: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: scheme.onPrimary,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: iconSize),
                  const SizedBox(width: AppSpacing.sm),
                  Text(label),
                ],
              ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (isIOS)
          socialButton(
            action: 'apple',
            icon: Icons.apple,
            iconSize: 22,
            label: 'Continue with Apple',
            onPressed: onApple,
          )
        else
          socialButton(
            action: 'google',
            icon: Icons.g_mobiledata_rounded,
            iconSize: 30,
            label: 'Continue with Google',
            onPressed: onGoogle,
          ),
        const SizedBox(height: AppSpacing.xl),
        Row(
          children: [
            Expanded(child: Divider(color: scheme.outlineVariant)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Text(
                'or',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            Expanded(child: Divider(color: scheme.outlineVariant)),
          ],
        ),
        const SizedBox(height: AppSpacing.xl),
        OutlinedButton.icon(
          onPressed: onEmail,
          icon: const Icon(Icons.mail_outline_rounded, size: 20),
          label: const Text('Continue with Email'),
        ),
      ],
    );
  }
}

class _EmailForm extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController email;
  final TextEditingController password;
  final bool isSignUp;
  final bool obscure;
  final bool isLoading;
  final VoidCallback onToggleObscure;
  final VoidCallback onToggleMode;
  final VoidCallback? onBack;
  final VoidCallback onSubmit;

  const _EmailForm({
    super.key,
    required this.formKey,
    required this.email,
    required this.password,
    required this.isSignUp,
    required this.obscure,
    required this.isLoading,
    required this.onToggleObscure,
    required this.onToggleMode,
    required this.onBack,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onPrimary = theme.colorScheme.onPrimary;

    return Form(
      key: formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'Back',
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back_rounded),
                visualDensity: VisualDensity.compact,
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                isSignUp ? 'Create your account' : 'Sign in with email',
                style: theme.textTheme.titleMedium,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          TextFormField(
            controller: email,
            enabled: !isLoading,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Email',
              prefixIcon: Icon(Icons.mail_outline_rounded),
            ),
            validator: (v) =>
                (v == null || !v.contains('@')) ? 'Enter a valid email' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: password,
            enabled: !isLoading,
            obscureText: obscure,
            decoration: InputDecoration(
              labelText: 'Password',
              prefixIcon: const Icon(Icons.lock_outline_rounded),
              suffixIcon: IconButton(
                onPressed: isLoading ? null : onToggleObscure,
                icon: Icon(
                  obscure
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
              ),
            ),
            validator: (v) => (v == null || v.length < 6)
                ? 'Password must be at least 6 characters'
                : null,
          ),
          const SizedBox(height: AppSpacing.xl),
          FilledButton(
            onPressed: isLoading ? null : onSubmit,
            child: isLoading
                ? SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: onPrimary,
                    ),
                  )
                : Text(isSignUp ? 'Create account' : 'Sign in'),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextButton(
            onPressed: isLoading ? null : onToggleMode,
            child: Text(
              isSignUp
                  ? 'Already have an account? Sign in'
                  : "Don't have an account? Sign up",
            ),
          ),
        ],
      ),
    );
  }
}
