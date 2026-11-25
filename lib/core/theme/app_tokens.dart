import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Design tokens for AnyChat+.
///
/// Direction: exact, quiet, a little technical. The app is an instrument for
/// watching what a model is doing with your context, so the chrome is ink and
/// hairlines, figures are monospaced, and exactly one signal colour carries
/// meaning. Nothing glows.
class AppRamp {
  const AppRamp({
    required this.background,
    required this.surface,
    required this.raised,
    required this.raisedHigh,
    required this.border,
    required this.borderStrong,
    required this.text,
    required this.textDim,
    required this.textMuted,
  });

  final Color background;
  final Color surface;
  final Color raised;
  final Color raisedHigh;
  final Color border;
  final Color borderStrong;
  final Color text;
  final Color textDim;
  final Color textMuted;

  static const AppRamp dark = AppRamp(
    background: Color(0xFF0D0E10),
    surface: Color(0xFF131417),
    raised: Color(0xFF17181C),
    raisedHigh: Color(0xFF1D1F24),
    border: Color(0xFF26282E),
    borderStrong: Color(0xFF33363D),
    text: Color(0xFFE9EAEC),
    textDim: Color(0xFF9BA0A7),
    textMuted: Color(0xFF6C7178),
  );

  static const AppRamp light = AppRamp(
    background: Color(0xFFFCFCFA),
    surface: Color(0xFFFFFFFF),
    raised: Color(0xFFF5F5F1),
    raisedHigh: Color(0xFFEDEDE7),
    border: Color(0xFFE3E3DC),
    borderStrong: Color(0xFFCDCDC4),
    text: Color(0xFF14161A),
    textDim: Color(0xFF565B62),
    textMuted: Color(0xFF868B92),
  );
}

/// The three shipped looks. `instrument` is the ink-and-hairlines treatment
/// with monospaced figures, `material` is Material You with seeded surfaces,
/// `glass` is Liquid Glass: translucent blurred panels over a colour field.
enum AppUiStyle { instrument, material, glass }

AppUiStyle appUiStyleFromName(String? name) {
  for (final AppUiStyle style in AppUiStyle.values) {
    if (style.name == name) return style;
  }
  return AppUiStyle.instrument;
}

class AppRadius {
  const AppRadius._();

  /// Buttons, fields, chips.
  static const double control = 10;

  /// Cards, code panes, message blocks.
  static const double card = 14;

  /// Sheets and dialogs.
  static const double panel = 20;
}

class AppSpace {
  const AppSpace._();

  static const double x1 = 4;
  static const double x2 = 8;
  static const double x3 = 12;
  static const double x4 = 16;
  static const double x5 = 20;
  static const double x6 = 24;
  static const double x8 = 32;
  static const double x10 = 40;
}

class AppMotion {
  const AppMotion._();

  /// One curve, three durations, everywhere.
  static const Curve curve = Curves.easeOutCubic;
  static const Duration fast = Duration(milliseconds: 120);
  static const Duration base = Duration(milliseconds: 200);
  static const Duration slow = Duration(milliseconds: 320);
}

class AppType {
  const AppType._();

  static const String sans = 'PlexSans';
  static const String mono = 'PlexMono';

  static TextTheme textTheme(Color primary, Color dim) {
    TextStyle base(double size, double height, FontWeight weight,
            {double? tracking}) =>
        TextStyle(
          fontFamily: sans,
          fontSize: size,
          height: height / size,
          fontWeight: weight,
          letterSpacing: tracking,
          fontVariations: <FontVariation>[
            ui.FontVariation('wght', _axis(weight)),
          ],
          color: primary,
        );

    return TextTheme(
      displayLarge: base(34, 40, FontWeight.w500, tracking: -0.8),
      displayMedium: base(30, 36, FontWeight.w500, tracking: -0.6),
      displaySmall: base(26, 32, FontWeight.w500, tracking: -0.4),
      headlineLarge: base(24, 30, FontWeight.w500, tracking: -0.3),
      headlineMedium: base(21, 27, FontWeight.w500, tracking: -0.2),
      headlineSmall: base(18, 25, FontWeight.w500, tracking: -0.1),
      titleLarge: base(17, 24, FontWeight.w500),
      titleMedium: base(15.5, 22, FontWeight.w500),
      titleSmall: base(13.5, 20, FontWeight.w500),
      bodyLarge: base(15.5, 24, FontWeight.w400),
      bodyMedium: base(15, 23, FontWeight.w400),
      bodySmall: base(13, 20, FontWeight.w400),
      labelLarge: base(14, 20, FontWeight.w500),
      labelMedium: base(12.5, 18, FontWeight.w500),
      labelSmall: base(11.5, 16, FontWeight.w500, tracking: 0.1),
    ).apply(bodyColor: primary, displayColor: primary).copyWith(
          bodySmall: base(13, 20, FontWeight.w400).copyWith(color: dim),
        );
  }

  static double _axis(FontWeight weight) => weight.value.toDouble();

  /// Figures, token counts, code and anything that must line up in a column.
  static TextStyle figure(
    double size, {
    FontWeight weight = FontWeight.w400,
    double height = 1.45,
    Color? color,
  }) =>
      TextStyle(
        fontFamily: mono,
        fontSize: size,
        height: height,
        fontWeight: weight,
        fontVariations: <FontVariation>[
          ui.FontVariation('wght', _axis(weight)),
        ],
        fontFeatures: const <ui.FontFeature>[ui.FontFeature.tabularFigures()],
        color: color,
      );

}
