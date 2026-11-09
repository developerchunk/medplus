import 'package:flutter/material.dart';

/// Brand + semantic colors used across the app.
class AppColors {
  static const brand = Color(0xFF0F766E); // teal 700
  static const brandLight = Color(0xFF14B8A6);
  static const danger = Color(0xFFDC2626);
  static const warning = Color(0xFFD97706);
  static const caution = Color(0xFFCA8A04);
  static const success = Color(0xFF16A34A);
  static const info = Color(0xFF2563EB);
  static const violet = Color(0xFF7C3AED);
  static const rx = Color(0xFFBE185D);
}

extension ThemeX on BuildContext {
  ThemeData get theme => Theme.of(this);
  ColorScheme get cs => Theme.of(this).colorScheme;
  TextTheme get tt => Theme.of(this).textTheme;
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
  Color get muted => Theme.of(this).colorScheme.onSurfaceVariant;
  Color get border => Theme.of(this).colorScheme.outlineVariant;
}

ThemeData buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final cs = ColorScheme.fromSeed(
    seedColor: AppColors.brand,
    brightness: brightness,
    primary: dark ? const Color(0xFF2DD4BF) : AppColors.brand,
    surface: dark ? const Color(0xFF151A1E) : Colors.white,
    surfaceContainerLowest: dark ? const Color(0xFF0E1215) : const Color(0xFFF5F7F8),
    surfaceContainerLow: dark ? const Color(0xFF1A2024) : const Color(0xFFF7F9FA),
    surfaceContainer: dark ? const Color(0xFF1E252A) : const Color(0xFFF1F4F5),
    surfaceContainerHigh: dark ? const Color(0xFF242C31) : const Color(0xFFEAEFF0),
    outlineVariant: dark ? const Color(0xFF2C353B) : const Color(0xFFE3E8EA),
  );
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: cs,
    fontFamily: 'NotoSans',
    brightness: brightness,
    visualDensity: VisualDensity.compact,
  );
  final radius = BorderRadius.circular(10);
  return base.copyWith(
    scaffoldBackgroundColor: cs.surfaceContainerLowest,
    textTheme: base.textTheme.apply(bodyColor: cs.onSurface, displayColor: cs.onSurface).copyWith(
          headlineSmall: base.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.3, fontSize: 22),
          titleLarge: base.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.2, fontSize: 18),
          titleMedium: base.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600, fontSize: 15),
          titleSmall: base.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600, fontSize: 13),
          bodyMedium: base.textTheme.bodyMedium?.copyWith(fontSize: 13.5),
          bodySmall: base.textTheme.bodySmall?.copyWith(fontSize: 12),
          labelMedium: base.textTheme.labelMedium?.copyWith(fontSize: 12, fontWeight: FontWeight.w500),
        ),
    cardTheme: CardThemeData(
      color: cs.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: cs.outlineVariant)),
    ),
    dividerTheme: DividerThemeData(color: cs.outlineVariant, thickness: 1, space: 1),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: dark ? const Color(0xFF1A2024) : const Color(0xFFF8FAFA),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: cs.outlineVariant)),
      enabledBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: cs.outlineVariant)),
      focusedBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: cs.primary, width: 1.6)),
      errorBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: cs.error)),
      labelStyle: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
      floatingLabelStyle: TextStyle(color: cs.primary, fontWeight: FontWeight.w600),
      hintStyle: TextStyle(color: cs.onSurfaceVariant.withValues(alpha: 0.7), fontSize: 13),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: radius),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5, fontFamily: 'NotoSans'),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: radius),
        side: BorderSide(color: cs.outlineVariant),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5, fontFamily: 'NotoSans'),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: radius),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5, fontFamily: 'NotoSans'),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: cs.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    chipTheme: base.chipTheme.copyWith(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      side: BorderSide(color: cs.outlineVariant),
    ),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 400),
      decoration: BoxDecoration(color: dark ? const Color(0xFF2C353B) : const Color(0xFF1F2937), borderRadius: BorderRadius.circular(6)),
      textStyle: const TextStyle(color: Colors.white, fontSize: 12),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      width: 460,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
        textStyle: const WidgetStatePropertyAll(TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, fontFamily: 'NotoSans')),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: cs.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: cs.outlineVariant)),
    ),
    scrollbarTheme: const ScrollbarThemeData(thickness: WidgetStatePropertyAll(6), radius: Radius.circular(3)),
  );
}
