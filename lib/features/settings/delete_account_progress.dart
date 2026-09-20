import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/responsive.dart';

/// The stages of closing an account, in the order they run.
enum DeleteStage {
  backup('Saving a backup', Icons.download_rounded),
  data('Removing your data', Icons.cloud_off_rounded),
  account('Closing your account', Icons.lock_person_rounded),
  done('Account closed', Icons.check_circle_rounded);

  const DeleteStage(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// Progress for a destructive, multi-step operation the user cannot cancel.
///
/// Deleting an account takes long enough that a bare spinner reads as a hang.
/// Naming each step, and marking the ones already finished, makes the wait
/// legible — and makes clear how far things got if it fails.
class DeleteAccountProgress extends StatelessWidget {
  final ValueListenable<DeleteStage> stage;

  /// Backup is optional, so it is hidden entirely when not chosen rather than
  /// shown as a step that never runs.
  final bool includesBackup;

  const DeleteAccountProgress({
    super.key,
    required this.stage,
    required this.includesBackup,
  });

  List<DeleteStage> get _steps => [
        if (includesBackup) DeleteStage.backup,
        DeleteStage.data,
        DeleteStage.account,
      ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return PopScope(
      // Leaving mid-delete would strand the account half-removed.
      canPop: false,
      child: Dialog(
        backgroundColor: scheme.surfaceContainer,
        insetPadding: const EdgeInsets.all(AppSpacing.xl),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.hero),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: ValueListenableBuilder<DeleteStage>(
            valueListenable: stage,
            builder: (context, current, _) {
              final finished = current == DeleteStage.done;
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Halo(done: finished),
                  const SizedBox(height: AppSpacing.xl),
                  Text(
                    // Distinct from the step labels below — repeating
                    // "Closing your account" in both places read as a bug.
                    finished ? 'Account closed' : 'Deleting your account',
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    finished
                        ? 'Everything has been removed. Taking you back to sign in.'
                        : 'This takes a few seconds. Please keep the app open.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  for (final step in _steps)
                    _StepRow(
                      step: step,
                      state: _stateOf(step, current),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  _StepState _stateOf(DeleteStage step, DeleteStage current) {
    if (current == DeleteStage.done) return _StepState.done;
    final order = _steps.indexOf(step);
    final currentOrder = _steps.indexOf(current);
    if (currentOrder < 0) return _StepState.pending;
    if (order < currentOrder) return _StepState.done;
    if (order == currentOrder) return _StepState.active;
    return _StepState.pending;
  }
}

enum _StepState { pending, active, done }

/// Pulsing ring while work is in flight, settling into a solid mark when done.
class _Halo extends StatefulWidget {
  final bool done;
  const _Halo({required this.done});

  @override
  State<_Halo> createState() => _HaloState();
}

class _HaloState extends State<_Halo> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = widget.done ? AppColors.income : scheme.error;
    final size = 58.rr;

    if (widget.done) _controller.stop();

    return SizedBox(
      width: size,
      height: size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final t = Curves.easeInOut.transform(
            (_controller.value * 2 <= 1)
                ? _controller.value * 2
                : 2 - _controller.value * 2,
          );
          return Stack(
            alignment: Alignment.center,
            children: [
              // Breathing halo: motion without a progress bar, because the
              // duration genuinely is not known.
              if (!widget.done)
                Container(
                  width: size * (0.72 + 0.28 * t),
                  height: size * (0.72 + 0.28 * t),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: accent.withValues(alpha: 0.10 + 0.10 * (1 - t)),
                  ),
                ),
              Container(
                width: size * 0.66,
                height: size * 0.66,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accent.withValues(alpha: 0.16),
                ),
                child: Icon(
                  widget.done
                      ? Icons.check_rounded
                      : Icons.delete_outline_rounded,
                  color: accent,
                  size: size * 0.34,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  final DeleteStage step;
  final _StepState state;

  const _StepRow({required this.step, required this.state});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final (color, leading) = switch (state) {
      _StepState.done => (
          AppColors.income,
          Icon(Icons.check_circle_rounded, size: 18.rr, color: AppColors.income),
        ),
      _StepState.active => (
          scheme.onSurface,
          SizedBox(
            width: 18.rr,
            height: 18.rr,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: scheme.primary,
            ),
          ),
        ),
      _StepState.pending => (
          scheme.onSurfaceVariant,
          Icon(
            Icons.circle_outlined,
            size: 18.rr,
            color: scheme.outlineVariant,
          ),
        ),
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        children: [
          leading,
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              style: theme.textTheme.bodyMedium!.copyWith(
                color: color,
                fontWeight: state == _StepState.active
                    ? FontWeight.w700
                    : FontWeight.w500,
              ),
              child: Text(step.label),
            ),
          ),
        ],
      ),
    );
  }
}
