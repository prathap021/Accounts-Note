import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../providers/app_lock_provider.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/app_logo.dart';

/// Puts the lock screen over the whole app while it is locked, and locks it
/// again after a while in the background. Only for a signed-in user: the
/// sign-in screen needs no lock.
class AppLockGate extends ConsumerStatefulWidget {
  const AppLockGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends ConsumerState<AppLockGate>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final lock = ref.read(appLockProvider.notifier);
    if (state == AppLifecycleState.paused) lock.appBackgrounded();
    if (state == AppLifecycleState.resumed) lock.appResumed();
  }

  @override
  Widget build(BuildContext context) {
    final locked = ref.watch(appLockProvider.select((s) => s.locked));
    final signedIn = ref.watch(currentUidProvider) != null;
    return Stack(
      children: [
        widget.child,
        // The gate sits above the app's router, so the lock screen gets a
        // navigator of its own for the "Forgot PIN?" dialog.
        if (locked && signedIn)
          Positioned.fill(
            child: HeroControllerScope.none(
              child: Navigator(
                onGenerateRoute: (_) => MaterialPageRoute<void>(
                  builder: (_) => const LockScreen(),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key});

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  String? _error;
  Timer? _tick;
  int _pinKey = 0;

  @override
  void initState() {
    super.initState();
    // Offer the fingerprint straight away when it is turned on.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && ref.read(appLockProvider).biometrics) {
        ref.read(appLockProvider.notifier).unlockWithBiometrics();
      }
    });
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && ref.read(appLockProvider).lockedOutUntil != null) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  void _submit(String pin) {
    final ok = ref.read(appLockProvider.notifier).unlock(pin);
    if (ok) return;
    HapticFeedback.heavyImpact();
    final s = ref.read(appLockProvider);
    setState(() {
      _pinKey++;
      _error = s.lockedOutUntil != null
          ? null
          : 'Wrong PIN. ${AppLockNotifier.maxFailures - s.failures} '
                '${AppLockNotifier.maxFailures - s.failures == 1 ? 'try' : 'tries'} '
                'left before a short wait.';
    });
  }

  Future<void> _forgot() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Forgot your PIN?'),
        content: const Text(
          'Sign out, then sign in again to prove it is you. The PIN is '
          'turned off; your data stays safe in the cloud and comes back '
          'when you sign in.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(appLockProvider.notifier).disable();
    await ref.read(authActionsProvider.notifier).signOut();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appLockProvider);
    final theme = Theme.of(context);
    final until = s.lockedOutUntil;
    final waiting = until != null && DateTime.now().isBefore(until);
    final secondsLeft = waiting
        ? until.difference(DateTime.now()).inSeconds + 1
        : 0;

    return Material(
      color: theme.scaffoldBackgroundColor,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const AppLogo(size: 64),
                const SizedBox(height: AppSpacing.lg),
                Text('Enter your PIN', style: theme.textTheme.titleLarge),
                const SizedBox(height: AppSpacing.sm),
                SizedBox(
                  height: 36,
                  child: Text(
                    waiting
                        ? 'Too many tries. Try again in $secondsLeft s.'
                        : _error ?? '',
                    key: const Key('lock-message'),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
                PinPad(
                  key: ValueKey(_pinKey),
                  enabled: !waiting,
                  onCompleted: _submit,
                  onBiometrics: s.biometrics
                      ? () => ref
                            .read(appLockProvider.notifier)
                            .unlockWithBiometrics()
                      : null,
                ),
                const SizedBox(height: AppSpacing.lg),
                TextButton(
                  onPressed: _forgot,
                  child: const Text('Forgot PIN?'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Four dots and a number pad. Calls [onCompleted] with the fourth digit.
class PinPad extends StatefulWidget {
  const PinPad({
    super.key,
    required this.onCompleted,
    this.onBiometrics,
    this.enabled = true,
  });

  final ValueChanged<String> onCompleted;
  final VoidCallback? onBiometrics;
  final bool enabled;

  @override
  State<PinPad> createState() => _PinPadState();
}

class _PinPadState extends State<PinPad> {
  String _pin = '';

  void _press(String digit) {
    if (!widget.enabled || _pin.length >= 4) return;
    HapticFeedback.selectionClick();
    setState(() => _pin += digit);
    if (_pin.length == 4) {
      final pin = _pin;
      Future<void>.delayed(const Duration(milliseconds: 120), () {
        if (mounted) widget.onCompleted(pin);
      });
    }
  }

  void _back() {
    if (_pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget key(String label, {VoidCallback? onTap, Widget? child}) => SizedBox(
      width: 72,
      height: 64,
      child: TextButton(
        key: Key('pin-$label'),
        onPressed: widget.enabled ? onTap : null,
        style: TextButton.styleFrom(shape: const CircleBorder()),
        child:
            child ??
            Text(label, style: Theme.of(context).textTheme.headlineSmall),
      ),
    );

    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < 4; i++)
              Container(
                margin: const EdgeInsets.all(AppSpacing.sm),
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i < _pin.length ? scheme.primary : Colors.transparent,
                  border: Border.all(color: scheme.primary, width: 2),
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        for (final row in const [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
        ])
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [for (final d in row) key(d, onTap: () => _press(d))],
          ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            widget.onBiometrics == null
                ? const SizedBox(width: 72, height: 64)
                : key(
                    'fingerprint',
                    onTap: widget.onBiometrics,
                    child: const Icon(Icons.fingerprint_rounded, size: 30),
                  ),
            key('0', onTap: () => _press('0')),
            key(
              'back',
              onTap: _back,
              child: const Icon(Icons.backspace_outlined),
            ),
          ],
        ),
      ],
    );
  }
}
