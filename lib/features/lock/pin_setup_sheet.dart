import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import 'lock_screen.dart';

/// Asks for a new PIN twice. Returns it, or null if cancelled.
Future<String?> askNewPin(BuildContext context) => showModalBottomSheet<String>(
  context: context,
  isScrollControlled: true,
  builder: (_) =>
      const _PinSheet(confirmTwice: true, title: 'Choose a 4-digit PIN'),
);

/// Asks for a PIN once (e.g. the current one before turning the lock off).
Future<String?> askPin(BuildContext context, String title) =>
    showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _PinSheet(confirmTwice: false, title: title),
    );

class _PinSheet extends StatefulWidget {
  const _PinSheet({required this.confirmTwice, required this.title});

  final bool confirmTwice;
  final String title;

  @override
  State<_PinSheet> createState() => _PinSheetState();
}

class _PinSheetState extends State<_PinSheet> {
  String? _first;
  String? _error;
  int _key = 0;

  void _completed(String pin) {
    if (!widget.confirmTwice) {
      Navigator.pop(context, pin);
      return;
    }
    if (_first == null) {
      setState(() {
        _first = pin;
        _error = null;
        _key++;
      });
    } else if (pin == _first) {
      Navigator.pop(context, pin);
    } else {
      setState(() {
        _first = null;
        _error = "The PINs didn't match. Choose one again.";
        _key++;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          0,
          AppSpacing.xl,
          AppSpacing.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _first == null ? widget.title : 'Enter the same PIN again',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              height: 24,
              child: Text(
                _error ?? '',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
            PinPad(key: ValueKey(_key), onCompleted: _completed),
          ],
        ),
      ),
    );
  }
}
