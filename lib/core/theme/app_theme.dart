import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

/// Accounts Note visual language — teal ledger, soft mist surfaces, no purple.
class AppColors {
  static const brand = Color(0xFF279698);
  static const brandDeep = Color(0xFF1A6B6D);
  static const brandSoft = Color(0xFFD5F5F6);
  static const income = Color(0xFF059669);
  static const expense = Color(0xFFE11D48);
  static const warning = Color(0xFFD97706);
  static const mist = Color(0xFFF0FDFA);
  static const ink = Color(0xFF0F172A);
  static const muted = Color(0xFF64748B);
}

class AppTheme {
  static ThemeData light() {
    final base = ColorScheme.fromSeed(
      seedColor: AppColors.brand,
      brightness: Brightness.light,
      primary: AppColors.brand,
      onPrimary: Colors.white,
      secondary: AppColors.brandDeep,
      surface: AppColors.mist,
      error: AppColors.expense,
    );

    return _base(
      scheme: base.copyWith(
        surfaceContainerLowest: Colors.white,
        surfaceContainerLow: const Color(0xFFF8FAFC),
        surfaceContainer: Colors.white,
        surfaceContainerHigh: Colors.white,
        surfaceContainerHighest: const Color(0xFFE2E8F0),
        outlineVariant: const Color(0xFFCBD5E1),
      ),
      scaffold: AppColors.mist,
    );
  }

  static ThemeData dark() {
    final base = ColorScheme.fromSeed(
      seedColor: AppColors.brand,
      brightness: Brightness.dark,
      primary: const Color(0xFF2DD4BF),
      onPrimary: const Color(0xFF042F2E),
      secondary: const Color(0xFF99F6E4),
      surface: const Color(0xFF0B1416),
      error: const Color(0xFFFB7185),
    );

    return _base(
      scheme: base.copyWith(
        surfaceContainerLowest: const Color(0xFF0B1416),
        surfaceContainerLow: const Color(0xFF111C1E),
        surfaceContainer: const Color(0xFF152225),
        surfaceContainerHigh: const Color(0xFF1A2A2E),
        surfaceContainerHighest: const Color(0xFF24363A),
        outlineVariant: const Color(0xFF334155),
      ),
      scaffold: const Color(0xFF0B1416),
    );
  }

  static ThemeData _base({
    required ColorScheme scheme,
    required Color scaffold,
  }) {
    final textTheme = GoogleFonts.plusJakartaSansTextTheme(
      ThemeData(brightness: scheme.brightness).textTheme,
    ).apply(
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scaffold,
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        systemOverlayStyle: scheme.brightness == Brightness.dark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 6,
        shadowColor: scheme.shadow.withValues(alpha: 0.08),
        color: scheme.surfaceContainer,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide.none,
        ),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainer,
        hintStyle: TextStyle(color: scheme.onSurfaceVariant),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(30),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(30),
          borderSide: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.2)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(30),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 32),
          shape: const StadiumBorder(),
          textStyle: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 32),
          shape: const StadiumBorder(),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
          textStyle: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 4,
        shape: const StadiumBorder(),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surfaceContainer,
        indicatorColor: scheme.primary.withValues(alpha: 0.1),
        indicatorShape: const StadiumBorder(),
        elevation: 8,
        shadowColor: scheme.shadow.withValues(alpha: 0.05),
        height: 80,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return textTheme.labelSmall?.copyWith(
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? scheme.primary : scheme.onSurfaceVariant,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? scheme.primary : scheme.onSurfaceVariant,
            size: 24,
          );
        }),
      ),
      chipTheme: ChipThemeData(
        shape: const StadiumBorder(),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.2)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.2),
        space: 24,
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: StadiumBorder(),
        elevation: 4,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainer,
        elevation: 10,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        showDragHandle: true,
      ),
    );
  }
}

/// Soft atmospheric wash behind login / splash.
class SoftMeshBackground extends StatelessWidget {
  final Widget child;
  const SoftMeshBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: dark
              ? const [Color(0xFF0B1416), Color(0xFF1A6B6D), Color(0xFF0B1416)]
              : const [Color(0xFFF0FDFA), Color(0xFFE0F2FE), Color(0xFFF8FAFC)],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -80,
            right: -40,
            child: _Blob(
              size: 220,
              color: (dark ? const Color(0xFF2DD4BF) : AppColors.brand)
                  .withValues(alpha: dark ? 0.12 : 0.14),
            ),
          ),
          Positioned(
            bottom: 80,
            left: -60,
            child: _Blob(
              size: 180,
              color: (dark ? const Color(0xFF38BDF8) : const Color(0xFF38BDF8))
                  .withValues(alpha: dark ? 0.1 : 0.12),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _Blob extends StatelessWidget {
  final double size;
  final Color color;
  const _Blob({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
        ),
      ),
    );
  }
}

class BalanceHeroCard extends StatelessWidget {
  final String label;
  final String amount;
  final String? subtitle;

  const BalanceHeroCard({
    super.key,
    required this.label,
    required this.amount,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(28, 32, 28, 32),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.brandDeep, AppColors.brand, Color(0xFF14B8A6)],
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.brand.withValues(alpha: 0.15),
            blurRadius: 32,
            spreadRadius: 4,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Colors.white,
                    letterSpacing: 0.5,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
          const SizedBox(height: 16),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.92, end: 1),
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeOutCubic,
            builder: (context, value, child) => Opacity(
              opacity: value.clamp(0.0, 1.0),
              child: Transform.translate(
                offset: Offset(0, (1 - value) * 12),
                child: child,
              ),
            ),
            child: Text(
              amount,
              style: Theme.of(context).textTheme.displaySmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1.5,
                    height: 1.1,
                  ),
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 8),
            Text(
              subtitle!,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.8),
                    fontWeight: FontWeight.w500,
                  ),
            ),
          ],
        ],
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  const SectionHeader({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
          ),
        ),
        if (actionLabel != null && onAction != null)
          TextButton(
            onPressed: onAction,
            child: Text(actionLabel!),
          ),
      ],
    );
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 32, color: scheme.primary),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}
