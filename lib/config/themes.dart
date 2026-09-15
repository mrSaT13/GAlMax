// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to galmax
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:galmax/config/app_config.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

abstract class GalmaxThemes {
  static const double columnWidth = 380.0;

  static const double maxTimelineWidth = columnWidth * 2;

  static const double navRailWidth = 80.0;

  static bool isColumnModeByWidth(double width) =>
      width > columnWidth * 2 + navRailWidth;

  static bool isColumnMode(BuildContext context) =>
      isColumnModeByWidth(MediaQuery.sizeOf(context).width);

  static bool isThreeColumnMode(BuildContext context) =>
      MediaQuery.sizeOf(context).width > GalmaxThemes.columnWidth * 3.5;

  static LinearGradient backgroundGradient(BuildContext context, int alpha) {
    final colorScheme = Theme.of(context).colorScheme;
    return LinearGradient(
      begin: Alignment.topCenter,
      colors: [
        colorScheme.primaryContainer.withAlpha(alpha),
        colorScheme.secondaryContainer.withAlpha(alpha),
        colorScheme.tertiaryContainer.withAlpha(alpha),
        colorScheme.primaryContainer.withAlpha(alpha),
      ],
    );
  }

  static const Duration animationDuration = Duration(milliseconds: 300);
  static const Curve animationCurve = Curves.easeOutCubic;

  // GAIMax default green color palette
  static const Color _greenPrimary = Color(0xFF2E7D32);
  static const Color _greenLight = Color(0xFF4CAF50);
  static const Color _greenDark = Color(0xFF1B5E20);
  static const Color _greenAccent = Color(0xFF66BB6A);

  static ColorScheme _buildColorScheme(Brightness brightness, Color? seed) {
    final isDark = brightness == Brightness.dark;

    if (seed != null) {
      return isDark
          ? ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark)
          : ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.light);
    }

    // Default GAlMax green theme when no custom seed is chosen
    return isDark
        ? ColorScheme.dark(
            primary: _greenLight,
            onPrimary: Colors.white,
            primaryContainer: _greenDark,
            onPrimaryContainer: _greenAccent,
            secondary: _greenAccent,
            onSecondary: Colors.black,
            secondaryContainer: const Color(0xFF2A3A2A),
            onSecondaryContainer: _greenLight,
            tertiary: const Color(0xFF81C784),
            onTertiary: Colors.black,
            tertiaryContainer: const Color(0xFF1A2E1A),
            onTertiaryContainer: const Color(0xFFA5D6A7),
            surface: AppConfig.darkSurface,
            onSurface: Colors.white,
            surfaceContainer: AppConfig.darkCard,
            surfaceContainerHighest: const Color(0xFF253525),
            surfaceContainerHigh: const Color(0xFF203020),
            surfaceContainerLow: const Color(0xFF152015),
            surfaceContainerLowest: const Color(0xFF0D150D),
            error: const Color(0xFFEF5350),
            onError: Colors.white,
            outline: const Color(0xFF4CAF50).withAlpha(80),
            outlineVariant: const Color(0xFF2E7D32).withAlpha(40),
          )
        : ColorScheme.light(
            primary: _greenDark,
            onPrimary: Colors.white,
            primaryContainer: _greenLight,
            onPrimaryContainer: _greenDark,
            secondary: _greenPrimary,
            onSecondary: Colors.white,
            secondaryContainer: const Color(0xFFC8E6C9),
            onSecondaryContainer: _greenDark,
            tertiary: const Color(0xFF388E3C),
            onTertiary: Colors.white,
            tertiaryContainer: const Color(0xFFE8F5E9),
            onTertiaryContainer: const Color(0xFF1B5E20),
            surface: const Color(0xFFF5F9F5),
            onSurface: const Color(0xFF1A1A1A),
            surfaceContainer: Colors.white,
            surfaceContainerHighest: const Color(0xFFE8F5E9),
            surfaceContainerHigh: const Color(0xFFF0F7F0),
            surfaceContainerLow: const Color(0xFFF8FBF8),
            surfaceContainerLowest: Colors.white,
            error: const Color(0xFFD32F2F),
            onError: Colors.white,
            outline: _greenPrimary.withAlpha(80),
            outlineVariant: _greenLight.withAlpha(40),
          );
  }

  static ThemeData buildTheme(
    BuildContext context,
    Brightness brightness, [
    Color? seed,
  ]) {
    final colorScheme = _buildColorScheme(brightness, seed);
    final isDark = brightness == Brightness.dark;
    final hasCustomSeed = seed != null;
    // При кастомном цвете не используем захардкоженные тёмно-зелёные
    // поверхности — иначе тема «не применяется» (остаётся зелёной).
    final darkSurface = hasCustomSeed
        ? colorScheme.surfaceContainer
        : AppConfig.darkCard;
    final darkBackground = hasCustomSeed
        ? colorScheme.surface
        : AppConfig.darkBackground;

    final isColumnMode = GalmaxThemes.isColumnMode(context);
    final dividerColor = isDark
        ? colorScheme.surfaceContainerHighest
        : colorScheme.surfaceContainer;

    return ThemeData(
      visualDensity: VisualDensity.standard,
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      // Запасной эмодзи-шрифт из APK ОТКЛЮЧЁН на тест (14.09.2026):
      // с ним на части прошивок текст едет вразрядку, разбираемся.
      // Было: fontFamilyFallback: const ['NotoColorEmoji'],
      dividerColor: dividerColor,
      scaffoldBackgroundColor: isDark ? darkBackground : null,
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          iconColor: colorScheme.onSurface,
          disabledIconColor: colorScheme.onSurface,
        ),
      ),
      textSelectionTheme: TextSelectionThemeData(
        selectionColor: colorScheme.primary.withAlpha(100),
        selectionHandleColor: colorScheme.primary,
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConfig.borderRadius / 2),
        ),
        contentPadding: const EdgeInsets.all(12),
        filled: true,
        fillColor: isDark ? darkSurface : null,
      ),
      chipTheme: ChipThemeData(
        showCheckmark: false,
        backgroundColor: colorScheme.surfaceContainer,
        side: BorderSide.none,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConfig.borderRadius),
        ),
      ),
      appBarTheme: AppBarTheme(
        toolbarHeight: isColumnMode ? 72 : 56,
        surfaceTintColor: isColumnMode ? colorScheme.surface : null,
        backgroundColor: isDark ? darkBackground : colorScheme.surface,
        actionsPadding: isColumnMode
            ? const EdgeInsets.symmetric(horizontal: 16.0)
            : null,
        elevation: 0,
        scrolledUnderElevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
          statusBarBrightness: brightness,
          systemNavigationBarIconBrightness:
              isDark ? Brightness.light : Brightness.dark,
          systemNavigationBarColor: isDark
              ? darkBackground
              : colorScheme.surface,
        ),
      ),
      cardTheme: CardThemeData(
        color: isDark ? darkSurface : null,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConfig.borderRadius),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: isDark ? darkSurface : null,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConfig.borderRadius),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: isDark ? darkSurface : null,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          side: BorderSide(width: 1, color: colorScheme.primary),
          shape: RoundedRectangleBorder(
            side: BorderSide(color: colorScheme.primary),
            borderRadius: BorderRadius.circular(AppConfig.borderRadius / 2),
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          elevation: 0,
          padding: const EdgeInsets.all(16),
          textStyle: const TextStyle(fontSize: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppConfig.borderRadius / 2),
          ),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        strokeCap: StrokeCap.round,
        color: colorScheme.primary,
        refreshBackgroundColor: colorScheme.primary.withAlpha(30),
      ),
      snackBarTheme: SnackBarThemeData(
        showCloseIcon: isColumnMode ? true : false,
        behavior: SnackBarBehavior.floating,
        width: isColumnMode ? GalmaxThemes.columnWidth * 1.5 : null,
        backgroundColor: isDark
            ? colorScheme.surfaceContainerHighest
            : colorScheme.primary,
        contentTextStyle: TextStyle(
          color: isDark ? colorScheme.onSurface : colorScheme.onPrimary,
        ),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
        },
      ),
    );
  }
}

extension BubbleColorTheme on ThemeData {
  Color get bubbleColor => colorScheme.primary;
  Color get onBubbleColor => colorScheme.onPrimary;
  Color get secondaryBubbleColor => colorScheme.surfaceContainerHigh;
}
