import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'responsive.dart';

/// Accounts Note visual language: a vivid violet lead colour with a
/// spectrum of friendly accents (orange, green, blue, pink, amber, teal) for
/// stats, categories and icons; airy neutral surfaces; soft shadows rather
/// than outlines; generous rounding; and one typeface (Figtree, bundled in
/// assets/fonts).
class AppColors {
  /// The logo and splash teal. Also one of the accent colours, so the logo
  /// belongs to the palette.
  static const brand = Color(0xFF279698);
  static const brandDeep = Color(0xFF0B5F61);
  static const brandSoft = Color(0xFFD5F5F6);

  /// The interactive colour: buttons, links, selection. White text on it,
  /// and it on white, pass WCAG AA (about 5.9:1).
  static const primary = Color(0xFF6246EA);
  static const primaryDeep = Color(0xFF4630C9);

  /// The primary for dark surfaces (dark mode, the loading panel).
  static const primaryLight = Color(0xFFA99BFF);

  // Accents.
  static const coral = Color(0xFFFF7A45);
  static const orange = Color(0xFFF97316);
  static const sky = Color(0xFF3B82F6);
  static const pink = Color(0xFFEC4899);
  static const amber = Color(0xFFF59E0B);
  static const teal = Color(0xFF14B8A6);

  static const income = Color(0xFF059669);
  static const expense = Color(0xFFE11D48);
  static const warning = Color(0xFFD97706);
  static const mist = Color(0xFFF0FDFA);
  static const ink = Color(0xFF14122B);
  static const muted = Color(0xFF64748B);

  /// App canvas behind cards: a faintly cool grey, so white cards lift off
  /// it.
  static const canvasLight = Color(0xFFF4F5FA);
  static const canvasDark = Color(0xFF0D0C1A);

  /// The dashboard header and other hero surfaces: violet into indigo-blue.
  /// White small text passes AA on its lightest corner.
  static const heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF7558FA), Color(0xFF5B45E8), Color(0xFF3B48D6)],
    stops: [0, 0.5, 1],
  );

  static const heroGradientDark = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF4B36C4), Color(0xFF3A2C9E), Color(0xFF26307F)],
    stops: [0, 0.5, 1],
  );

  /// Friendly tints for icon tiles (settings rows and the like), picked by
  /// name so each row keeps its colour.
  static const tilePalette = [
    Color(0xFF6246EA), // violet
    Color(0xFF2563EB), // blue
    Color(0xFFEA580C), // orange
    Color(0xFF059669), // emerald
    Color(0xFFDB2777), // pink
    Color(0xFF0284C7), // sky
    Color(0xFFD97706), // amber
    Color(0xFF0D9488), // teal
  ];

  static Color tileColorFor(String key) =>
      tilePalette[key.codeUnits.fold<int>(
            0,
            (a, c) => (a * 31 + c) & 0x7fffffff,
          ) %
          tilePalette.length];
}

/// One radius scale, used everywhere instead of ad-hoc numbers.
class AppRadii {
  static const double control = 16; // inputs, buttons
  static const double card = 22; // cards, list surfaces, groups
  static const double hero = 28; // hero/balance card, bottom sheets, dialogs
  static const double pill = 999;
}

/// One spacing scale. Screens use [screenPadding] for their horizontal gutter
/// so every page lines up on the same vertical rhythm.
class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;

  /// Horizontal gutter shared by every screen.
  static const double gutter = 16;

  /// Bottom padding that keeps scroll content clear of the FAB + nav bar.
  static const double scrollBottom = 112;

  static const screenPadding = EdgeInsets.symmetric(horizontal: gutter);
}

/// Shadows for light mode. Dark mode uses hairline outlines instead, since
/// shadows vanish on a dark canvas.
class AppShadows {
  /// Resting cards.
  static const soft = [
    BoxShadow(color: Color(0x0A0F172A), blurRadius: 2, offset: Offset(0, 1)),
    BoxShadow(color: Color(0x0D0F172A), blurRadius: 20, offset: Offset(0, 8)),
  ];

  /// Raised surfaces: the hero card, floating buttons.
  static const raised = [
    BoxShadow(color: Color(0x0F0F172A), blurRadius: 4, offset: Offset(0, 2)),
    BoxShadow(color: Color(0x140F172A), blurRadius: 32, offset: Offset(0, 14)),
  ];

  static List<BoxShadow>? of(BuildContext context, {bool raised = false}) =>
      Theme.of(context).brightness == Brightness.dark
      ? null
      : (raised ? AppShadows.raised : AppShadows.soft);
}

class AppTheme {
  /// The app's typeface, declared in pubspec.yaml.
  static const fontFamily = 'Figtree';

  static ThemeData light() {
    final base = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.light,
      primary: AppColors.primary,
      onPrimary: Colors.white,
      secondary: AppColors.coral,
      surface: AppColors.canvasLight,
      error: AppColors.expense,
    );

    return _base(
      scheme: base.copyWith(
        primaryContainer: const Color(0xFFE7E2FF),
        onPrimaryContainer: const Color(0xFF22106E),
        onSurface: const Color(0xFF14122B),
        surfaceContainerLowest: Colors.white,
        surfaceContainerLow: const Color(0xFFF8FAFB),
        surfaceContainer: Colors.white,
        surfaceContainerHigh: const Color(0xFFEFF0F7),
        surfaceContainerHighest: const Color(0xFFE4E6F1),
        outline: const Color(0xFFC6C9DA),
        outlineVariant: const Color(0xFFE4E6F1),
        onSurfaceVariant: const Color(0xFF5E6278),
        shadow: AppColors.ink,
      ),
      scaffold: AppColors.canvasLight,
    );
  }

  static ThemeData dark() {
    final base = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.dark,
      primary: AppColors.primaryLight,
      onPrimary: const Color(0xFF1A1060),
      secondary: const Color(0xFFFFB38F),
      surface: AppColors.canvasDark,
      error: const Color(0xFFFB7185),
    );

    return _base(
      scheme: base.copyWith(
        primaryContainer: const Color(0xFF2E2370),
        onPrimaryContainer: const Color(0xFFE2DDFF),
        surfaceContainerLowest: const Color(0xFF0D0C1A),
        surfaceContainerLow: const Color(0xFF131223),
        surfaceContainer: const Color(0xFF18172B),
        surfaceContainerHigh: const Color(0xFF211F38),
        surfaceContainerHighest: const Color(0xFF2A2844),
        outline: const Color(0xFF45435F),
        outlineVariant: const Color(0xFF2B2A45),
        onSurfaceVariant: const Color(0xFFA9A8C2),
      ),
      scaffold: AppColors.canvasDark,
    );
  }

  /// Multiplies every font size by [factor], leaving styles that declare no
  /// size untouched.
  static TextTheme _scaleTextTheme(TextTheme base, double factor) {
    if (factor == 1.0) return base;

    TextStyle? scale(TextStyle? style) {
      final size = style?.fontSize;
      if (style == null || size == null) return style;
      return style.copyWith(fontSize: size * factor);
    }

    return base.copyWith(
      displayLarge: scale(base.displayLarge),
      displayMedium: scale(base.displayMedium),
      displaySmall: scale(base.displaySmall),
      headlineLarge: scale(base.headlineLarge),
      headlineMedium: scale(base.headlineMedium),
      headlineSmall: scale(base.headlineSmall),
      titleLarge: scale(base.titleLarge),
      titleMedium: scale(base.titleMedium),
      titleSmall: scale(base.titleSmall),
      bodyLarge: scale(base.bodyLarge),
      bodyMedium: scale(base.bodyMedium),
      bodySmall: scale(base.bodySmall),
      labelLarge: scale(base.labelLarge),
      labelMedium: scale(base.labelMedium),
      labelSmall: scale(base.labelSmall),
    );
  }

  static ThemeData _base({
    required ColorScheme scheme,
    required Color scaffold,
  }) {
    final dark = scheme.brightness == Brightness.dark;

    // One factor scales every text style in the app, so type stays in
    // proportion on a small phone and a large one alike.
    //
    // Note: TextTheme.apply(fontSizeFactor:) cannot be used here. It asserts
    // that every style carries an explicit fontSize, and this text theme has
    // styles that do not — which crashes on the first frame at any scale
    // other than 1.0. _scaleTextTheme skips those instead.
    //
    // Material's own 2021 typography is the base because it declares an
    // explicit fontSize for every style. `ThemeData(...).textTheme` leaves
    // them null and resolves sizes later, which would make the scaling below
    // a silent no-op.
    final typography = Typography.material2021();
    final sized = typography.englishLike.merge(
      dark ? typography.white : typography.black,
    );

    final textTheme = _scaleTextTheme(sized, Responsive.textScale).apply(
      fontFamily: fontFamily,
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
    );

    // Figtree reads best a touch heavier than Material's defaults, with
    // tighter tracking on large sizes and a little air in body copy.
    final headings = textTheme.copyWith(
      displaySmall: textTheme.displaySmall?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -1.2,
      ),
      headlineMedium: textTheme.headlineMedium?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -0.8,
      ),
      headlineSmall: textTheme.headlineSmall?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -0.6,
      ),
      titleLarge: textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -0.4,
      ),
      titleMedium: textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.1,
      ),
      titleSmall: textTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
      ),
      bodyLarge: textTheme.bodyLarge?.copyWith(
        fontWeight: FontWeight.w500,
        letterSpacing: 0,
        height: 1.4,
      ),
      bodyMedium: textTheme.bodyMedium?.copyWith(
        fontWeight: FontWeight.w500,
        letterSpacing: 0,
        height: 1.4,
      ),
      bodySmall: textTheme.bodySmall?.copyWith(
        fontWeight: FontWeight.w500,
        letterSpacing: 0.1,
        height: 1.35,
      ),
      labelLarge: textTheme.labelLarge?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
      ),
      labelMedium: textTheme.labelMedium?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
      ),
      labelSmall: textTheme.labelSmall?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: 0.2,
      ),
    );

    final border = scheme.outlineVariant;
    final control = BorderRadius.circular(AppRadii.control);
    // Cards and fields lift off the canvas with shadow in light mode, and
    // with a hairline in dark mode, where shadows disappear.
    final cardSide = dark ? BorderSide(color: border) : BorderSide.none;

    OutlineInputBorder field(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: control,
          borderSide: BorderSide(color: color, width: width),
        );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: fontFamily,
      scaffoldBackgroundColor: scaffold,
      textTheme: headings,
      primaryTextTheme: headings,
      splashFactory: InkSparkle.splashFactory,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: scaffold,
        surfaceTintColor: Colors.transparent,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        systemOverlayStyle: dark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
        titleTextStyle: headings.titleLarge,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shadowColor: scheme.shadow.withValues(alpha: 0.06),
        color: scheme.surfaceContainer,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.card),
          side: cardSide,
        ),
        margin: EdgeInsets.zero,
      ),
      // Filled fields with no outline until focused: lighter on the eye
      // than a stack of boxes, and the focused one is unmistakable.
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? scheme.surfaceContainerHigh : scheme.surfaceContainerHigh,
        hintStyle: headings.bodyLarge?.copyWith(
          color: scheme.onSurfaceVariant.withValues(alpha: 0.8),
          fontWeight: FontWeight.w500,
        ),
        labelStyle: headings.bodyLarge?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
        floatingLabelStyle: TextStyle(
          color: scheme.primary,
          fontWeight: FontWeight.w700,
        ),
        helperStyle: headings.bodySmall?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
        prefixIconColor: scheme.onSurfaceVariant,
        suffixIconColor: scheme.onSurfaceVariant,
        border: field(Colors.transparent),
        enabledBorder: field(Colors.transparent),
        disabledBorder: field(Colors.transparent),
        focusedBorder: field(scheme.primary, 1.8),
        errorBorder: field(scheme.error.withValues(alpha: 0.8)),
        focusedErrorBorder: field(scheme.error, 1.8),
        contentPadding: EdgeInsets.symmetric(horizontal: 16.rw, vertical: 18.rh),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          elevation: 0,
          // Height only. `Size.fromHeight` would set an INFINITE minimum
          // width, which asserts wherever width is unbounded (a Row, dialog
          // actions); 64 is Material's own default minimum width.
          minimumSize: Size(64.rw, 54.rh),
          padding: EdgeInsets.symmetric(vertical: 16.rh, horizontal: 24.rw),
          shape: RoundedRectangleBorder(borderRadius: control),
          textStyle: headings.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: 0.1,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: Size(64.rw, 54.rh),
          padding: EdgeInsets.symmetric(vertical: 16.rh, horizontal: 24.rw),
          shape: RoundedRectangleBorder(borderRadius: control),
          side: BorderSide(color: dark ? scheme.outline : scheme.outline.withValues(alpha: 0.7)),
          backgroundColor: scheme.surfaceContainerLowest,
          foregroundColor: scheme.onSurface,
          textStyle: headings.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          shape: RoundedRectangleBorder(borderRadius: control),
          textStyle: headings.labelLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: scheme.onSurface,
          highlightColor: scheme.primary.withValues(alpha: 0.08),
        ),
      ),
      // A pill toggle: grey track, the chosen option filled with the accent.
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          textStyle: WidgetStatePropertyAll(
            headings.labelLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          side: const WidgetStatePropertyAll(BorderSide.none),
          elevation: const WidgetStatePropertyAll(0),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            return states.contains(WidgetState.selected)
                ? scheme.primary
                : scheme.surfaceContainerHigh;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            return states.contains(WidgetState.selected)
                ? scheme.onPrimary
                : scheme.onSurfaceVariant;
          }),
          iconColor: WidgetStateProperty.resolveWith((states) {
            return states.contains(WidgetState.selected)
                ? scheme.onPrimary
                : scheme.onSurfaceVariant;
          }),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          visualDensity: VisualDensity.standard,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 4,
        focusElevation: 4,
        hoverElevation: 6,
        highlightElevation: 6,
        extendedPadding: const EdgeInsets.symmetric(horizontal: 22),
        extendedTextStyle: headings.titleMedium?.copyWith(
          fontWeight: FontWeight.w800,
          color: scheme.onPrimary,
        ),
        shape: const StadiumBorder(),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        indicatorColor: scheme.primary.withValues(alpha: dark ? 0.22 : 0.12),
        indicatorShape: const StadiumBorder(),
        elevation: 0,
        height: 70.rh,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return headings.labelMedium?.copyWith(
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            color: selected ? scheme.primary : scheme.onSurfaceVariant,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? scheme.primary : scheme.onSurfaceVariant,
            size: 24.rr,
          );
        }),
      ),
      // Tonal chips: filled grey at rest; the chosen one tinted with the
      // accent, outlined and in accent text.
      chipTheme: ChipThemeData(
        shape: const StadiumBorder(),
        side: WidgetStateBorderSide.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? BorderSide(color: scheme.primary, width: 1.4)
              : const BorderSide(color: Colors.transparent),
        ),
        backgroundColor: scheme.surfaceContainerHigh,
        selectedColor: scheme.primary.withValues(alpha: dark ? 0.22 : 0.12),
        checkmarkColor: scheme.primary,
        showCheckmark: false,
        labelStyle: WidgetStateTextStyle.resolveWith(
          (states) =>
              (headings.labelLarge ?? const TextStyle()).copyWith(
                fontWeight: FontWeight.w700,
                color: states.contains(WidgetState.selected)
                    ? scheme.primary
                    : scheme.onSurface,
              ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: scheme.onSurfaceVariant,
        titleTextStyle: headings.bodyLarge?.copyWith(
          fontWeight: FontWeight.w600,
          color: scheme.onSurface,
        ),
        subtitleTextStyle: headings.bodySmall?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        shape: RoundedRectangleBorder(borderRadius: control),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Colors.white
              : (dark ? scheme.outline : Colors.white),
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? scheme.primary
              : scheme.surfaceContainerHighest,
        ),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
      dividerTheme: DividerThemeData(color: border, space: 24, thickness: 1),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: dark ? scheme.surfaceContainerHighest : AppColors.ink,
        contentTextStyle: headings.bodyMedium?.copyWith(
          color: dark ? scheme.onSurface : Colors.white,
          fontWeight: FontWeight.w600,
        ),
        actionTextColor: dark ? scheme.primary : const Color(0xFFC4B8FF),
        shape: RoundedRectangleBorder(borderRadius: control),
        insetPadding: const EdgeInsets.all(AppSpacing.lg),
        elevation: 6,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        elevation: 12,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.hero),
        ),
        titleTextStyle: headings.titleLarge,
        contentTextStyle: headings.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: dark ? scheme.surfaceContainer : scheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.hero)),
        ),
        showDragHandle: true,
        dragHandleColor: scheme.outline.withValues(alpha: 0.6),
        dragHandleSize: const Size(40, 5),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: scheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: control),
        textStyle: headings.bodyMedium,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.surfaceContainerHighest,
        circularTrackColor: Colors.transparent,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: scheme.primary,
        inactiveTrackColor: scheme.surfaceContainerHighest,
        thumbColor: scheme.primary,
        overlayColor: scheme.primary.withValues(alpha: 0.12),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: scheme.primary,
        unselectedLabelColor: scheme.onSurfaceVariant,
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: border,
        labelStyle: headings.titleSmall,
        unselectedLabelStyle:
            headings.titleSmall?.copyWith(fontWeight: FontWeight.w500),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: dark ? scheme.surfaceContainerHighest : AppColors.ink,
          borderRadius: BorderRadius.circular(10),
        ),
        textStyle: headings.labelMedium?.copyWith(
          color: dark ? scheme.onSurface : Colors.white,
        ),
      ),
    );
  }
}

/// Soft atmospheric wash behind login / splash / onboarding.
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
              ? const [Color(0xFF0D0C1A), Color(0xFF1C1840), Color(0xFF0D0C1A)]
              : const [Color(0xFFF5F2FF), Color(0xFFEEF3FF), Color(0xFFFFF6F1)],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -90,
            right: -50,
            child: _Blob(
              size: 240.rr,
              color: (dark ? const Color(0xFF8B7BFF) : AppColors.primary)
                  .withValues(alpha: dark ? 0.16 : 0.16),
            ),
          ),
          Positioned(
            bottom: 60,
            left: -70,
            child: _Blob(
              size: 200.rr,
              color: AppColors.coral.withValues(alpha: dark ? 0.12 : 0.14),
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
          gradient: RadialGradient(
            colors: [color, color.withValues(alpha: 0)],
          ),
        ),
      ),
    );
  }
}

/// The single card surface used across the app: same radius, same soft lift.
/// Screens should not hand-roll `BoxDecoration`.
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;
  final bool elevated;
  final double radius;

  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.onTap,
    this.color,
    this.elevated = false,
    this.radius = AppRadii.card,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final borderRadius = BorderRadius.circular(radius);

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: AppShadows.of(context, raised: elevated),
      ),
      child: Material(
        color: color ?? scheme.surfaceContainer,
        clipBehavior: Clip.antiAlias,
        // Material asserts if both `shape` and `borderRadius` are given, so the
        // radius lives on the shape only.
        shape: RoundedRectangleBorder(
          borderRadius: borderRadius,
          side: dark ? BorderSide(color: scheme.outlineVariant) : BorderSide.none,
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: borderRadius,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// A tinted rounded-square icon tile, the app's one way of putting an icon
/// beside a label (settings rows, details rows, empty states).
class IconTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;

  const IconTile({
    super.key,
    required this.icon,
    required this.color,
    this.size = 40,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: dark ? 0.22 : 0.12),
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      child: Icon(icon, size: size * 0.5, color: color),
    );
  }
}

/// Shared page header for the four primary tabs so every screen announces
/// itself the same way: a quiet eyebrow, a big title, optional actions.
class AppSliverHeader extends StatelessWidget {
  final String title;
  final String? eyebrow;
  final List<Widget> actions;
  final Widget? leading;

  const AppSliverHeader({
    super.key,
    required this.title,
    this.eyebrow,
    this.actions = const [],
    this.leading,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SliverAppBar(
      floating: true,
      toolbarHeight: 80.rh,
      automaticallyImplyLeading: false,
      titleSpacing: AppSpacing.gutter + 2,
      leading: leading,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (eyebrow != null)
            Text(
              eyebrow!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          const SizedBox(height: 2),
          // Scale down rather than ellipsize: a long display name should stay
          // fully readable instead of being cut to "Prathap Kum…".
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              title,
              maxLines: 1,
              softWrap: false,
              style: theme.textTheme.headlineMedium?.copyWith(
                fontSize: (theme.textTheme.headlineSmall?.fontSize ?? 24) + 2,
              ),
            ),
          ),
        ],
      ),
      actions: [
        ...actions,
        const SizedBox(width: AppSpacing.sm),
      ],
    );
  }
}

/// Round icon button used in page headers, so every screen's top-right
/// affordance has the same size and lift.
class HeaderAction extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool highlighted;

  const HeaderAction({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onTap,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.sm),
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: highlighted ? null : AppShadows.of(context),
        ),
        child: IconButton(
          tooltip: tooltip,
          onPressed: onTap,
          style: IconButton.styleFrom(
            fixedSize: const Size(46, 46),
            backgroundColor: highlighted
                ? scheme.primary.withValues(alpha: 0.14)
                : scheme.surfaceContainerLowest,
            foregroundColor: highlighted ? scheme.primary : scheme.onSurface,
            disabledForegroundColor: scheme.onSurfaceVariant.withValues(alpha: 0.4),
            shape: CircleBorder(
              side: dark && !highlighted
                  ? BorderSide(color: scheme.outlineVariant)
                  : BorderSide.none,
            ),
          ),
          icon: Icon(icon, size: 22),
        ),
      ),
    );
  }
}

/// Hero balance panel on the dashboard: the brand gradient, the amount in
/// large white type, and a status pill saying whether the month is up or
/// down.
class BalanceHeroCard extends StatelessWidget {
  final String label;
  final String amount;
  final String? subtitle;

  /// e.g. "September 2026" — shown as a quiet chip beside the label.
  final String? periodLabel;

  /// Drives the Saved / Over pill.
  final bool isPositive;
  final Widget? footer;

  const BalanceHeroCard({
    super.key,
    required this.label,
    required this.amount,
    this.subtitle,
    this.periodLabel,
    this.isPositive = true,
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    const onHero = Colors.white;
    final radius = BorderRadius.circular(AppRadii.hero);

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: dark ? AppColors.heroGradientDark : AppColors.heroGradient,
        boxShadow: dark
            ? null
            : [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.32),
                  blurRadius: 30,
                  offset: const Offset(0, 14),
                ),
              ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(
          children: [
            // Two soft rings for depth; purely decorative.
            const Positioned(
              top: -70,
              right: -50,
              child: _Ring(size: 200, alpha: 0.10),
            ),
            const Positioned(
              bottom: -90,
              right: 60,
              child: _Ring(size: 170, alpha: 0.07),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          label.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: onHero.withValues(alpha: 0.82),
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.1,
                          ),
                        ),
                      ),
                      if (periodLabel != null) ...[
                        _HeroChip(
                          color: onHero.withValues(alpha: 0.16),
                          child: Text(
                            periodLabel!,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: onHero,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                      ],
                      _HeroChip(
                        color: isPositive
                            ? onHero.withValues(alpha: 0.18)
                            : const Color(0xFFFFE4E8),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isPositive
                                  ? Icons.trending_up_rounded
                                  : Icons.trending_down_rounded,
                              size: 15,
                              color: isPositive ? onHero : AppColors.expense,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              isPositive ? 'Saved' : 'Over',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: isPositive ? onHero : AppColors.expense,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  // The amount gets the card's full width, and scales down
                  // rather than wrapping for very large balances.
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
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        amount,
                        maxLines: 1,
                        style: theme.textTheme.displaySmall?.copyWith(
                          color: onHero,
                          fontWeight: FontWeight.w800,
                          fontSize: (theme.textTheme.displaySmall?.fontSize ?? 36) + 4,
                          letterSpacing: -1.4,
                          height: 1.1,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      subtitle!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: onHero.withValues(alpha: 0.82),
                        height: 1.4,
                      ),
                    ),
                  ],
                  if (footer != null) ...[
                    const SizedBox(height: AppSpacing.xl),
                    footer!,
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroChip extends StatelessWidget {
  const _HeroChip({required this.color, required this.child});

  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 6),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(AppRadii.pill),
    ),
    child: child,
  );
}

class _Ring extends StatelessWidget {
  const _Ring({required this.size, required this.alpha});

  final double size;
  final double alpha;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white.withValues(alpha: alpha),
          width: 26,
        ),
      ),
    ),
  );
}

class SectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontSize: (theme.textTheme.titleMedium?.fontSize ?? 16) + 2,
                ),
              ),
              if (subtitle != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    subtitle!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (actionLabel != null && onAction != null)
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              backgroundColor: scheme.primary.withValues(alpha: 0.08),
              shape: const StadiumBorder(),
              padding: const EdgeInsets.symmetric(horizontal: 14),
            ),
            child: Text(actionLabel!),
          ),
      ],
    );
  }
}

/// A quiet uppercase label that groups a stack of cards (Settings, Reports).
class SectionLabel extends StatelessWidget {
  final String text;
  const SectionLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: AppSpacing.sm, bottom: AppSpacing.sm),
      child: Text(
        text.toUpperCase(),
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.1,
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: AppSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 76.rr,
            height: 76.rr,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  scheme.primary.withValues(alpha: 0.18),
                  scheme.primary.withValues(alpha: 0.06),
                ],
              ),
            ),
            child: Icon(icon, size: 34.rr, color: scheme.primary),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.45,
            ),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: AppSpacing.xl),
            FilledButton.icon(
              onPressed: onAction,
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 50),
                padding: const EdgeInsets.symmetric(horizontal: 24),
                shape: const StadiumBorder(),
              ),
              icon: const Icon(Icons.add_rounded, size: 20),
              label: Text(actionLabel!),
            ),
          ],
        ],
      ),
    );
  }
}

/// Failure placeholder with a retry affordance — replaces the bare
/// "Something went wrong" strings that used to leave users stuck.
class AppErrorState extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  final bool compact;

  const AppErrorState({
    super.key,
    this.message = 'Something went wrong. Please try again.',
    this.onRetry,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return AppCard(
      padding: EdgeInsets.all(compact ? AppSpacing.lg : AppSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconTile(icon: Icons.cloud_off_rounded, color: scheme.error, size: 48),
          const SizedBox(height: AppSpacing.md),
          Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: AppSpacing.md),
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Try again'),
            ),
          ],
        ],
      ),
    );
  }
}

/// Shimmering placeholder block used by the loading skeletons.
class SkeletonBox extends StatefulWidget {
  final double? width;
  final double height;
  final double radius;

  const SkeletonBox({
    super.key,
    this.width,
    required this.height,
    this.radius = AppRadii.control,
  });

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    // Tinted from the text colour, so the placeholder stands out from both
    // the canvas and the cards it sits on, and the sweep is plainly visible.
    final base = Color.alphaBlend(
      scheme.onSurface.withValues(alpha: dark ? 0.10 : 0.11),
      scheme.surface,
    );
    final highlight = Color.alphaBlend(
      dark
          ? scheme.onSurface.withValues(alpha: 0.22)
          : Colors.white.withValues(alpha: 0.85),
      base,
    );

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        // A narrow bright band sweeping left to right, fully off both edges
        // between passes.
        final t = _controller.value * 3 - 1.5;
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            gradient: LinearGradient(
              begin: Alignment(t - 1, -0.3),
              end: Alignment(t + 1, 0.3),
              colors: [base, base, highlight, base, base],
              stops: const [0, 0.35, 0.5, 0.65, 1],
            ),
          ),
        );
      },
    );
  }
}
