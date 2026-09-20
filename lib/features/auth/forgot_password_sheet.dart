import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/responsive.dart';
import '../../providers/auth_provider.dart';

/// Password reset by email link.
///
/// Opens as a sheet from the sign-in form so the user never loses the email
/// they already typed.
Future<void> showForgotPasswordSheet(
  BuildContext context, {
  String? initialEmail,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _ForgotPasswordSheet(initialEmail: initialEmail),
  );
}

class _ForgotPasswordSheet extends ConsumerStatefulWidget {
  final String? initialEmail;
  const _ForgotPasswordSheet({this.initialEmail});

  @override
  ConsumerState<_ForgotPasswordSheet> createState() =>
      _ForgotPasswordSheetState();
}

class _ForgotPasswordSheetState extends ConsumerState<_ForgotPasswordSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _email =
      TextEditingController(text: widget.initialEmail ?? '');

  bool _sending = false;
  bool _sent = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _sending = true;
      _error = null;
    });

    final result = await ref
        .read(authActionsProvider.notifier)
        .requestPasswordReset(_email.text);

    if (!mounted) return;
    setState(() => _sending = false);
    result.when(
      success: (_) => setState(() => _sent = true),
      failure: (f) => setState(() => _error = f.userMessage),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.xl,
        right: AppSpacing.xl,
        top: AppSpacing.sm,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.xl,
      ),
      child: SingleChildScrollView(
        child: _sent ? _confirmation(theme, scheme) : _form(theme, scheme),
      ),
    );
  }

  Widget _form(ThemeData theme, ColorScheme scheme) {
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Reset your password', style: theme.textTheme.titleLarge),
          const SizedBox(height: AppSpacing.sm),
          Text(
            "Enter the email you registered with and we'll send you a link to "
            'choose a new password.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.45,
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          TextFormField(
            controller: _email,
            autofocus: true,
            enabled: !_sending,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              labelText: 'Email',
              prefixIcon: const Icon(Icons.mail_outline_rounded),
              errorText: _error,
            ),
            validator: (v) => (v == null || !v.contains('@'))
                ? 'Enter a valid email'
                : null,
            onFieldSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: AppSpacing.xl),
          FilledButton(
            onPressed: _sending ? null : _submit,
            child: _sending
                ? SizedBox(
                    height: 20.rr,
                    width: 20.rr,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: scheme.onPrimary,
                    ),
                  )
                : const Text('Send reset link'),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextButton(
            onPressed: _sending ? null : () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  Widget _confirmation(ThemeData theme, ColorScheme scheme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Container(
            padding: EdgeInsets.all(16.rr),
            decoration: BoxDecoration(
              color: AppColors.income.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.mark_email_read_outlined,
              size: 28.rr,
              color: AppColors.income,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text('Check your inbox', style: theme.textTheme.titleLarge),
        const SizedBox(height: AppSpacing.sm),
        Text(
          // Definite wording: unregistered addresses are rejected before
          // reaching this screen, so there is nothing left to hedge about.
          'We sent a reset link to ${_email.text.trim()}. It can take a '
          'minute to arrive, and may land in spam.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
            height: 1.45,
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Done'),
        ),
        const SizedBox(height: AppSpacing.sm),
        TextButton(
          onPressed: () => setState(() => _sent = false),
          child: const Text('Use a different email'),
        ),
      ],
    );
  }
}
