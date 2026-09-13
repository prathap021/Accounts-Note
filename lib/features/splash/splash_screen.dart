import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../widgets/app_logo.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SoftMeshBackground(
        child: Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.85, end: 1),
            duration: const Duration(milliseconds: 700),
            curve: Curves.easeOutCubic,
            builder: (context, value, child) => Opacity(
              opacity: value.clamp(0.0, 1.0),
              child: Transform.scale(scale: value, child: child),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const AppLogo(size: 96),
                const SizedBox(height: 20),
                Text(
                  'Accounts Note',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.6,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Loading your ledger…',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: scheme.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
