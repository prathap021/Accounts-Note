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
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.brand, AppColors.brandDeep],
        ),
        borderRadius: rounded ? BorderRadius.circular(size * 0.25) : null,
        boxShadow: rounded
            ? [
                BoxShadow(
                  color: AppColors.brandDeep.withValues(alpha: 0.3),
                  blurRadius: size * 0.25,
                  offset: Offset(0, size * 0.1),
                )
              ]
            : null,
      ),
      child: Center(
        child: Icon(
          Icons.currency_exchange_outlined,
          color: Colors.white,
          size: size * 0.55,
        ),
      ),
    );
  }
}
