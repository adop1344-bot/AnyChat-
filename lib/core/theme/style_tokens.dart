import 'package:flutter/material.dart';

import 'app_tokens.dart';

/// Per-style shape and type decisions that a color scheme cannot express.
///
/// `instrument` is dense and ink-flat: hairlines, monospaced figures, small
/// radii, 34-38px rows. `material` is Material You: tonal fills, rounder
/// corners, the stock type scale, 48px rows. Widgets read these instead of
/// hardcoding one look.
@immutable
class StyleTokens extends ThemeExtension<StyleTokens> {
  const StyleTokens({
    required this.instrument,
    required this.controlRadius,
    required this.cardRadius,
    required this.panelRadius,
    required this.monoFigures,
    required this.rowHeight,
    required this.hairlineChrome,
    required this.tonalChrome,
  });

  final bool instrument;
  final double controlRadius;
  final double cardRadius;
  final double panelRadius;

  /// Figures, token counts and model ids set in the mono family.
  final bool monoFigures;

  /// List rows in the drawer and sheets.
  final double rowHeight;

  /// Chrome separates with 1px rules on flat surfaces.
  final bool hairlineChrome;

  /// Chrome separates with tonal containers instead of rules.
  final bool tonalChrome;

  static const StyleTokens ink = StyleTokens(
    instrument: true,
    controlRadius: AppRadius.control,
    cardRadius: AppRadius.card,
    panelRadius: AppRadius.panel,
    monoFigures: true,
    rowHeight: 38,
    hairlineChrome: true,
    tonalChrome: false,
  );

  static const StyleTokens you = StyleTokens(
    instrument: false,
    controlRadius: 20,
    cardRadius: 16,
    panelRadius: 28,
    monoFigures: false,
    rowHeight: 48,
    hairlineChrome: false,
    tonalChrome: true,
  );

  static StyleTokens forStyle(AppUiStyle style) =>
      style == AppUiStyle.instrument ? ink : you;

  static StyleTokens of(BuildContext context) =>
      Theme.of(context).extension<StyleTokens>() ?? ink;

  BorderRadius get control => BorderRadius.circular(controlRadius);
  BorderRadius get card => BorderRadius.circular(cardRadius);
  BorderRadius get panel => BorderRadius.circular(panelRadius);

  @override
  StyleTokens copyWith({
    bool? instrument,
    double? controlRadius,
    double? cardRadius,
    double? panelRadius,
    bool? monoFigures,
    double? rowHeight,
    bool? hairlineChrome,
    bool? tonalChrome,
  }) =>
      StyleTokens(
        instrument: instrument ?? this.instrument,
        controlRadius: controlRadius ?? this.controlRadius,
        cardRadius: cardRadius ?? this.cardRadius,
        panelRadius: panelRadius ?? this.panelRadius,
        monoFigures: monoFigures ?? this.monoFigures,
        rowHeight: rowHeight ?? this.rowHeight,
        hairlineChrome: hairlineChrome ?? this.hairlineChrome,
        tonalChrome: tonalChrome ?? this.tonalChrome,
      );

  @override
  StyleTokens lerp(ThemeExtension<StyleTokens>? other, double t) {
    if (other is! StyleTokens) return this;
    return StyleTokens(
      instrument: t < 0.5 ? instrument : other.instrument,
      controlRadius:
          _lerp(controlRadius, other.controlRadius, t),
      cardRadius: _lerp(cardRadius, other.cardRadius, t),
      panelRadius: _lerp(panelRadius, other.panelRadius, t),
      monoFigures: t < 0.5 ? monoFigures : other.monoFigures,
      rowHeight: _lerp(rowHeight, other.rowHeight, t),
      hairlineChrome: t < 0.5 ? hairlineChrome : other.hairlineChrome,
      tonalChrome: t < 0.5 ? tonalChrome : other.tonalChrome,
    );
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;
}
