import 'package:flutter/material.dart';

/// Clean, iOS-adjacent Material 3 theme (system UI fonts with SF-like metrics).
class AktifTheme {
  static const _seed = Color(0xFF4F46E5); // indigo-600

  static ThemeData light() => _base(Brightness.light);
  static ThemeData dark() => _base(Brightness.dark);

  static ThemeData _base(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: brightness,
    );
    final isDark = brightness == Brightness.dark;
    final text = _textTheme(scheme, isDark);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: brightness,
      visualDensity: VisualDensity.standard,
      scaffoldBackgroundColor: isDark ? const Color(0xFF0B0B0F) : const Color(0xFFF7F7FA),
      textTheme: text,
      primaryTextTheme: text,
      appBarTheme: AppBarTheme(
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        backgroundColor: isDark ? const Color(0xFF0B0B0F) : const Color(0xFFF7F7FA),
        foregroundColor: scheme.onSurface,
        titleTextStyle: text.titleLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: isDark ? const Color(0xFF16161D) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: const EdgeInsets.symmetric(vertical: 6),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: -0.2),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? const Color(0xFF1C1C24) : const Color(0xFFF0F0F5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        side: BorderSide.none,
        padding: const EdgeInsets.symmetric(horizontal: 4),
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.4),
        space: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  static TextTheme _textTheme(ColorScheme scheme, bool isDark) {
    // SF-like: slightly tight tracking on titles, comfortable body.
    final base = isDark ? Typography.whiteMountainView : Typography.blackMountainView;
    TextStyle tighten(TextStyle? s, {double tracking = -0.4, FontWeight? w}) =>
        (s ?? const TextStyle()).copyWith(
          letterSpacing: tracking,
          fontWeight: w,
          height: 1.25,
        );
    return base.copyWith(
      displayLarge: tighten(base.displayLarge, tracking: -1.2, w: FontWeight.w700),
      displayMedium: tighten(base.displayMedium, tracking: -1.0, w: FontWeight.w700),
      displaySmall: tighten(base.displaySmall, tracking: -0.8, w: FontWeight.w700),
      headlineLarge: tighten(base.headlineLarge, tracking: -0.8, w: FontWeight.w700),
      headlineMedium: tighten(base.headlineMedium, tracking: -0.6, w: FontWeight.w600),
      headlineSmall: tighten(base.headlineSmall, tracking: -0.5, w: FontWeight.w600),
      titleLarge: tighten(base.titleLarge, tracking: -0.4, w: FontWeight.w600),
      titleMedium: tighten(base.titleMedium, tracking: -0.3, w: FontWeight.w600),
      titleSmall: tighten(base.titleSmall, tracking: -0.2, w: FontWeight.w600),
      bodyLarge: (base.bodyLarge ?? const TextStyle()).copyWith(height: 1.4, letterSpacing: -0.1),
      bodyMedium: (base.bodyMedium ?? const TextStyle()).copyWith(height: 1.4, letterSpacing: -0.05),
      bodySmall: (base.bodySmall ?? const TextStyle()).copyWith(height: 1.35, color: scheme.onSurfaceVariant),
      labelLarge: tighten(base.labelLarge, tracking: -0.1, w: FontWeight.w600),
    );
  }
}

/// FontWeight.w600 is not a const in older SDKs — map via w600 if needed.
extension on FontWeight {
  // ignore: unused_element
  static FontWeight get w650 => FontWeight.w600;
}
