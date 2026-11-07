import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// How long the second back press has to arrive for it to count as "exit".
/// Matches the snackbar's visible lifetime, so the window is something the
/// user can see rather than guess at.
const kDoubleBackWindow = Duration(seconds: 2);

/// Whether a back press should close the app, given when the previous one was.
///
/// A backwards clock jump (NTP correction, manual change) would otherwise
/// read as "a moment ago" and exit on a single press, so a negative gap is
/// treated as no previous press at all.
bool shouldExitOnBack({
  required DateTime? lastPress,
  required DateTime now,
  Duration window = kDoubleBackWindow,
}) {
  if (lastPress == null) return false;
  final elapsed = now.difference(lastPress);
  if (elapsed.isNegative) return false;
  return elapsed <= window;
}

/// Android's back behaviour for the app's root: back returns to the home tab
/// from anywhere else, and only leaves the app on a confirmed second press.
///
/// Without this, back on any tab drops straight out of the app, which loses
/// the user's place for the sake of one stray press.
class DoubleBackToExit extends StatefulWidget {
  final Widget child;

  /// True on the tab that back exits from. Anywhere else, back goes there
  /// first via [onReturnHome].
  final bool atHome;
  final VoidCallback onReturnHome;

  final Duration window;
  final String message;

  /// Injected by tests. Defaults to closing the app.
  final VoidCallback? onExit;

  const DoubleBackToExit({
    super.key,
    required this.child,
    required this.atHome,
    required this.onReturnHome,
    this.window = kDoubleBackWindow,
    this.message = 'Press back again to exit',
    this.onExit,
  });

  @override
  State<DoubleBackToExit> createState() => _DoubleBackToExitState();
}

class _DoubleBackToExitState extends State<DoubleBackToExit> {
  DateTime? _lastPress;

  void _handleBack() {
    if (!widget.atHome) {
      // Arriving home must need its own two presses, or a back from Activity
      // followed by one more would leave the app without warning.
      _lastPress = null;
      widget.onReturnHome();
      return;
    }

    final now = DateTime.now();
    if (shouldExitOnBack(
      lastPress: _lastPress,
      now: now,
      window: widget.window,
    )) {
      (widget.onExit ?? SystemNavigator.pop)();
      return;
    }

    _lastPress = now;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(widget.message),
          duration: widget.window,
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // The root of the app: there is nothing to pop to, so every back press
      // is handled here rather than by the navigator.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handleBack();
      },
      child: widget.child,
    );
  }
}
