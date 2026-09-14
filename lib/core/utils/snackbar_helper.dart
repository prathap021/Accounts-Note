import 'package:flutter/material.dart';

class SnackbarHelper {
  static void showSuccess(BuildContext context, String message) {
    _show(context, message, Colors.green.shade600);
  }

  static void showError(BuildContext context, String message) {
    _show(context, message, Colors.red.shade600);
  }

  static void _show(BuildContext context, String message, Color color) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
