import 'package:flutter/material.dart';

import '../core/colors.dart';

ThemeData buildTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(
    seedColor: googleBlue,
    brightness: brightness,
  ).copyWith(primary: brightness == Brightness.light ? googleBlue : const Color(0xFF8AB4F8));
  final base = ThemeData(useMaterial3: true, colorScheme: scheme);
  return base.copyWith(
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      elevation: 0,
      titleTextStyle: base.textTheme.titleLarge!.copyWith(
        color: scheme.onSurface,
        fontSize: 22,
        fontWeight: FontWeight.w400,
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: brightness == Brightness.light
          ? const Color(0xFFD3E3FD)
          : const Color(0xFF004A77),
      foregroundColor: brightness == Brightness.light
          ? const Color(0xFF041E49)
          : const Color(0xFFC2E7FF),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant, thickness: 1, space: 1),
    navigationDrawerTheme: NavigationDrawerThemeData(
      indicatorColor: scheme.primaryContainer,
    ),
  );
}

/// Colors used by the calendar grids.
extension CalendarColors on ColorScheme {
  Color get gridLine => outlineVariant.withValues(alpha: 0.6);
  Color get mutedText => onSurfaceVariant;
  Color get nowIndicator => const Color(0xFFEA4335);
}
