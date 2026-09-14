import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

/// Brand mark used on splash, login, and other chrome.
class AppLogo extends StatelessWidget {
  final double size;
  final bool rounded;

  const AppLogo({
    super.key,
    this.size = 72,
    this.rounded = true,
  });

  @override
  Widget build(BuildContext context) {
    final radius = rounded ? BorderRadius.circular(size * 0.22) : BorderRadius.zero;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: rounded
            ? [
                BoxShadow(
                  color: AppColors.brandDeep.withValues(alpha: 0.22),
                  blurRadius: size * 0.22,
                  offset: Offset(0, size * 0.08),
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Image.asset(
          'assets/branding/app_logo.png',
          width: size,
          height: size,
          fit: BoxFit.contain,
          alignment: Alignment.center,
          filterQuality: FilterQuality.high,
          errorBuilder: (context, error, stackTrace) {
            return ColoredBox(
              color: AppColors.brand,
              child: Icon(
                Icons.account_balance_wallet_rounded,
                color: Colors.white,
                size: size * 0.5,
              ),
            );
          },
        ),
      ),
    );
  }
}
