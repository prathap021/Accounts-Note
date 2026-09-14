import 'package:flutter/material.dart';

class SnackbarHelper {
  static void showSuccess(BuildContext context, String message) {
    _show(ScaffoldMessenger.of(context), message, Colors.green.shade600);
  }

  static void showError(BuildContext context, String message) {
    _show(ScaffoldMessenger.of(context), message, Colors.red.shade600);
  }

  static void showSuccessMessenger(ScaffoldMessengerState messenger, String message) {
    _show(messenger, message, Colors.green.shade600);
  }

  static void showErrorMessenger(ScaffoldMessengerState messenger, String message) {
    _show(messenger, message, Colors.red.shade600);
  }

  static void _show(ScaffoldMessengerState messenger, String message, Color color) {
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
