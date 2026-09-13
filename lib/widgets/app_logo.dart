import 'package:flutter/material.dart';

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
    final image = Image.asset(
      'assets/branding/app_logo.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
    );

    if (!rounded) return image;

    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.22),
      child: image,
    );
  }
}
