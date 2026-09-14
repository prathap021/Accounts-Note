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
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: rounded ? BorderRadius.circular(size * 0.25) : null,
        boxShadow: rounded
            ? [
                BoxShadow(
                  color: AppColors.brandDeep.withValues(alpha: 0.15),
                  blurRadius: size * 0.25,
                  offset: Offset(0, size * 0.1),
                )
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: rounded ? BorderRadius.circular(size * 0.25) : BorderRadius.zero,
        child: Image.asset(
          'assets/branding/app_logo.png',
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            // Fallback just in case the image is missing
            return Container(
              width: size,
              height: size,
              color: AppColors.brand,
              child: Icon(
                Icons.account_balance_wallet,
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
