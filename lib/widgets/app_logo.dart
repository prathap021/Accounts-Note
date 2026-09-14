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
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Main Notebook Icon
          Positioned(
            left: size * 0.2,
            child: Icon(
              Icons.menu_book_rounded,
              color: Colors.white.withValues(alpha: 0.95),
              size: size * 0.55,
            ),
          ),
          // Up Arrow (Income)
          Positioned(
            right: size * 0.15,
            top: size * 0.2,
            child: Container(
              padding: EdgeInsets.all(size * 0.04),
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.arrow_upward_rounded,
                color: AppColors.income,
                size: size * 0.22,
                weight: 700,
              ),
            ),
          ),
          // Down Arrow (Expense)
          Positioned(
            right: size * 0.15,
            bottom: size * 0.2,
            child: Container(
              padding: EdgeInsets.all(size * 0.04),
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.arrow_downward_rounded,
                color: AppColors.expense,
                size: size * 0.22,
                weight: 700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
