import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/result.dart';
import '../../providers/auth_provider.dart';

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

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final actions = ref.read(authActionsProvider.notifier);
    final actionState = ref.watch(authActionsProvider);

    ref.listen(authActionsProvider, (prev, next) {
      if (next is AsyncError) {
        final err = next.error;
        final message = err is AppFailure
            ? err.message
            : 'Something went wrong.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      }
    });

    final isLoading = actionState.isLoading;
    final isIOS = !kIsWeb && Platform.isIOS;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Center(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.account_balance_wallet_rounded, size: 72),
                  const SizedBox(height: 16),
                  Text(
                    'Track every rupee.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Sign in to sync your income and expenses everywhere.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 32),

                  if (!_showEmailForm) ...[
                    if (!isIOS)
                      FilledButton.icon(
                        onPressed: isLoading ? null : actions.signInWithGoogle,
                        icon: const Icon(Icons.g_mobiledata, size: 28),
                        label: const Text('Continue with Google'),
                      ),
                    if (isIOS)
                      FilledButton.icon(
                        onPressed: isLoading ? null : actions.signInWithApple,
                        icon: const Icon(Icons.apple),
                        label: const Text('Continue with Apple'),
                      ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: () => setState(() => _showEmailForm = true),
                      child: const Text('Continue with Email'),
                    ),
                  ] else ...[
                    Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          TextFormField(
                            controller: _email,
                            keyboardType: TextInputType.emailAddress,
                            decoration: const InputDecoration(labelText: 'Email'),
                            validator: (v) =>
                                (v == null || !v.contains('@')) ? 'Enter a valid email' : null,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _password,
                            obscureText: true,
                            decoration: const InputDecoration(labelText: 'Password'),
                            validator: (v) => (v == null || v.length < 6)
                                ? 'Password must be at least 6 characters'
                                : null,
                          ),
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed: isLoading
                                ? null
                                : () {
                                    if (!_formKey.currentState!.validate()) return;
                                    if (_isSignUp) {
                                      actions.signUpWithEmail(_email.text, _password.text);
                                    } else {
                                      actions.signInWithEmail(_email.text, _password.text);
                                    }
                                  },
                            child: isLoading
                                ? const SizedBox(
                                    height: 20, width: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2))
                                : Text(_isSignUp ? 'Sign Up' : 'Sign In'),
                          ),
                          TextButton(
                            onPressed: () => setState(() => _isSignUp = !_isSignUp),
                            child: Text(_isSignUp
                                ? 'Already have an account? Sign in'
                                : "Don't have an account? Sign up"),
                          ),
                          TextButton(
                            onPressed: () => setState(() => _showEmailForm = false),
                            child: const Text('Back'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
