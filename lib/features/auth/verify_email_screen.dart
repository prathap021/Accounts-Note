import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/responsive.dart';
import '../../core/utils/snackbar_helper.dart';
import '../../providers/auth_provider.dart';

/// Shown to email/password accounts until their address is confirmed.
///
/// Google and Apple users never reach this screen — those providers vouch for
/// the address, so gating them would be a pointless extra step.
class VerifyEmailScreen extends ConsumerStatefulWidget {
  const VerifyEmailScreen({super.key});

  @override
  ConsumerState<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends ConsumerState<VerifyEmailScreen>
    with WidgetsBindingObserver {
  /// Firebase rate-limits verification sends, so the button is held for a
  /// minute rather than letting the user earn a `too-many-requests` error.
  static const _resendCooldown = Duration(seconds: 60);

  Timer? _cooldownTimer;
  int _secondsUntilResend = 0;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startCooldown();
    // Safety net: if the send at sign-up never happened — a dropped
    // connection, a rate limit — the user would otherwise sit here waiting
    // for an email that was never sent.
    WidgetsBinding.instance.addPostFrameCallback((_) => _sendIfNeverSent());
  }

  Future<void> _sendIfNeverSent() async {
    final uid = ref.read(authStateProvider).asData?.value?.uid;
    if (uid == null) return;
    if (ref.read(authActionsProvider.notifier).hasSentVerificationFor(uid)) {
      return;
    }
    final result =
        await ref.read(authActionsProvider.notifier).sendEmailVerification();
    if (!mounted) return;
    result.when(
      success: (_) => SnackbarHelper.showSuccess(
        context,
        'Verification email sent',
      ),
      failure: (f) => SnackbarHelper.showError(context, f.userMessage),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cooldownTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The link is opened outside the app — in Gmail, or a browser. Coming back
    // is the one moment worth re-checking, so the user does not have to tap
    // anything. Checked once per return, not on a timer.
    if (state == AppLifecycleState.resumed) {
      _check(userInitiated: false);
    }
  }

  void _startCooldown() {
    setState(() => _secondsUntilResend = _resendCooldown.inSeconds);
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return timer.cancel();
      setState(() => _secondsUntilResend--);
      if (_secondsUntilResend <= 0) timer.cancel();
    });
  }

  /// Reloads from Firebase. On success the auth stream emits and the router
  /// moves the user on, so there is nothing to navigate here.
  ///
  /// [userInitiated] false means this came from returning to the app, where a
  /// "not verified yet" toast would be noise — the user may have switched away
  /// for an unrelated reason.
  Future<void> _check({bool userInitiated = true}) async {
    if (_checking) return;
    setState(() => _checking = true);
    final verified =
        await ref.read(authActionsProvider.notifier).refreshEmailVerification();
    if (!mounted) return;
    setState(() => _checking = false);

    if (!verified && userInitiated) {
      SnackbarHelper.showError(
        context,
        "That address isn't confirmed yet. Open the link in your inbox, then try again.",
      );
    }
  }

  Future<void> _resend() async {
    final result =
        await ref.read(authActionsProvider.notifier).sendEmailVerification();
    if (!mounted) return;
    result.when(
      success: (_) {
        SnackbarHelper.showSuccess(context, 'Verification email sent');
        _startCooldown();
      },
      failure: (f) => SnackbarHelper.showError(context, f.userMessage),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final email = ref.watch(pendingVerificationEmailProvider);
    final canResend = _secondsUntilResend <= 0;

    return Scaffold(
      body: SoftMeshBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xl,
                vertical: AppSpacing.xxl,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        padding: EdgeInsets.all(20.rr),
                        decoration: BoxDecoration(
                          color: scheme.primary.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.mark_email_unread_outlined,
                          size: 34.rr,
                          color: scheme.primary,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    Text(
                      'Confirm your email',
                      style: theme.textTheme.displaySmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -1.2,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text.rich(
                      TextSpan(
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: scheme.onSurfaceVariant,
                          height: 1.45,
                        ),
                        children: [
                          const TextSpan(text: 'We sent a confirmation link to '),
                          TextSpan(
                            text: email ?? 'your inbox',
                            style: TextStyle(
                              color: scheme.onSurface,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const TextSpan(
                            text: '. Open it, then come back here.',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    AppCard(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Row(
                        children: [
                          Icon(
                            Icons.autorenew_rounded,
                            size: 18.rr,
                            color: scheme.primary,
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: Text(
                              'Open the link, then return here — we check as '
                              'soon as you come back.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    FilledButton(
                      onPressed: _checking ? null : () => _check(),
                      child: _checking
                          ? SizedBox(
                              height: 20.rr,
                              width: 20.rr,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: scheme.onPrimary,
                              ),
                            )
                          : const Text("I've confirmed it"),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    OutlinedButton(
                      onPressed: canResend ? _resend : null,
                      child: Text(
                        canResend
                            ? 'Resend email'
                            : 'Resend in ${_secondsUntilResend}s',
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    TextButton(
                      onPressed: () =>
                          ref.read(authActionsProvider.notifier).signOut(),
                      child: const Text('Use a different account'),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      "Can't find it? Check your spam folder — the link can take a minute to arrive.",
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
