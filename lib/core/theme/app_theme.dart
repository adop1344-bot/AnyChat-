import 'package:flutter/material.dart';

import 'app_tokens.dart';

/// Builds the single theme used across AnyChat+.
///
/// Surfaces never take the accent: they come from one neutral ramp, so the
/// only colour on screen is the accent, and it only marks action, selection
/// or the one number that matters.
class AppTheme {
  const AppTheme._();

  static ThemeData light(Color accent, AppUiStyle style) =>
      _for(Brightness.light, accent, style);

  static ThemeData dark(Color accent, AppUiStyle style) =>
      _for(Brightness.dark, accent, style);

  static ThemeData _for(
    Brightness brightness,
    Color accent,
    AppUiStyle style,
  ) =>
      switch (style) {
        AppUiStyle.instrument => _build(brightness, accent),
        AppUiStyle.material => _material(brightness, accent),
      };

  /// Material You: seeded surfaces, tonal fills, pill controls, the stock type
  /// scale. Nothing from the instrument ramp leaks in here.
  static ThemeData _material(Brightness brightness, Color accent) {
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: brightness,
    );
    final bool isDark = brightness == Brightness.dark;
    final BorderRadius control = BorderRadius.circular(20);
    final BorderRadius card = BorderRadius.circular(16);
    final BorderRadius panel = BorderRadius.circular(28);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      splashFactory: InkSparkle.splashFactory,
      scaffoldBackgroundColor:
          isDark ? scheme.surfaceContainerLowest : scheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: scheme.surfaceTint,
        elevation: 0,
        scrolledUnderElevation: 3,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w400,
          color: scheme.onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: card),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: scheme.onSurfaceVariant,
        shape: RoundedRectangleBorder(borderRadius: control),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: panel),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: scheme.surfaceContainerLow,
        elevation: 0,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: TextStyle(color: scheme.onInverseSurface),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(
          alpha: isDark ? 0.35 : 0.55,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: control,
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: control,
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: control,
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          minimumSize: const Size(0, 44),
          shape: RoundedRectangleBorder(borderRadius: control),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(0, 40),
          shape: RoundedRectangleBorder(borderRadius: control),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 44),
          shape: RoundedRectangleBorder(borderRadius: control),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: control),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        selectedColor: scheme.secondaryContainer,
        side: BorderSide(color: scheme.outlineVariant),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: scheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: card),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.surfaceContainerHighest,
        circularTrackColor: scheme.surfaceContainerHighest,
        linearMinHeight: 2,
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        width: 300,
        shape: const RoundedRectangleBorder(),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: scheme.inverseSurface,
          borderRadius: BorderRadius.circular(6),
        ),
        textStyle: TextStyle(color: scheme.onInverseSurface),
      ),
    );
  }

  static ThemeData _build(Brightness brightness, Color accent) {
    final bool isDark = brightness == Brightness.dark;
    final AppRamp ramp = isDark ? AppRamp.dark : AppRamp.light;
    final ColorScheme seeded = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: brightness,
    );

    final ColorScheme scheme = seeded.copyWith(
      primary: seeded.primary,
      onPrimary: seeded.onPrimary,
      primaryContainer: seeded.primaryContainer,
      onPrimaryContainer: seeded.onPrimaryContainer,
      secondary: ramp.textDim,
      onSecondary: ramp.surface,
      secondaryContainer: ramp.raisedHigh,
      onSecondaryContainer: ramp.text,
      surface: ramp.surface,
      onSurface: ramp.text,
      onSurfaceVariant: ramp.textDim,
      surfaceTint: Colors.transparent,
      surfaceContainerLowest:
          isDark ? const Color(0xFF0A0B0C) : const Color(0xFFFCFCFA),
      surfaceContainerLow: ramp.raised,
      surfaceContainer:
          isDark ? const Color(0xFF1A1C20) : const Color(0xFFF2F2ED),
      surfaceContainerHigh: ramp.raisedHigh,
      surfaceContainerHighest:
          isDark ? const Color(0xFF23262B) : const Color(0xFFE8E8E1),
      outline: ramp.textMuted,
      outlineVariant: ramp.border,
      error: isDark ? const Color(0xFFE98C84) : const Color(0xFFB3261E),
      onError: isDark ? const Color(0xFF2B100D) : const Color(0xFFFFFFFF),
      inverseSurface: isDark ? ramp.text : const Color(0xFF1B1D21),
      onInverseSurface: isDark ? const Color(0xFF14161A) : ramp.text,
    );

    final TextTheme text = AppType.textTheme(ramp.text, ramp.textDim);
    final BorderRadius control = BorderRadius.circular(AppRadius.control);
    final BorderRadius card = BorderRadius.circular(AppRadius.card);
    final BorderSide hairline = BorderSide(color: ramp.border, width: 1);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      fontFamily: AppType.sans,
      textTheme: text,
      primaryTextTheme: text,
      scaffoldBackgroundColor: ramp.background,
      canvasColor: ramp.surface,
      splashFactory: InkRipple.splashFactory,
      splashColor: ramp.text.withValues(alpha: 0.04),
      highlightColor: ramp.text.withValues(alpha: 0.03),
      hoverColor: ramp.text.withValues(alpha: 0.04),
      dividerColor: ramp.border,
      iconTheme: IconThemeData(size: 20, color: ramp.textDim),
      appBarTheme: AppBarTheme(
        backgroundColor: ramp.background,
        foregroundColor: ramp.text,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        toolbarHeight: 56,
        titleSpacing: 16,
        titleTextStyle: text.titleLarge,
        iconTheme: IconThemeData(size: 20, color: ramp.textDim),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: ramp.raised,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: card),
      ),
      dividerTheme: DividerThemeData(
        color: ramp.border,
        thickness: 1,
        space: 1,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: ramp.textDim,
        textColor: ramp.text,
        titleTextStyle: text.titleMedium,
        subtitleTextStyle: text.bodySmall?.copyWith(color: ramp.textDim),
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpace.x4),
        minVerticalPadding: AppSpace.x3,
        shape: RoundedRectangleBorder(borderRadius: control),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: ramp.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.panel),
          side: hairline,
        ),
        titleTextStyle: text.headlineSmall,
        contentTextStyle: text.bodyMedium?.copyWith(color: ramp.textDim),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: ramp.surface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: ramp.surface,
        elevation: 0,
        showDragHandle: true,
        dragHandleColor: ramp.borderStrong,
        dragHandleSize: const Size(36, 4),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.panel),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: text.bodySmall?.copyWith(
          color: scheme.onInverseSurface,
        ),
        elevation: 0,
        insetPadding: const EdgeInsets.all(AppSpace.x4),
        shape: RoundedRectangleBorder(borderRadius: control),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: ramp.raised,
        isDense: false,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpace.x3 + 2,
          vertical: AppSpace.x3,
        ),
        hintStyle: text.bodyMedium?.copyWith(color: ramp.textMuted),
        labelStyle: text.bodySmall?.copyWith(color: ramp.textDim),
        floatingLabelStyle: text.labelMedium?.copyWith(color: ramp.textDim),
        helperStyle: text.bodySmall?.copyWith(color: ramp.textMuted),
        errorStyle: text.bodySmall?.copyWith(color: scheme.error),
        border: OutlineInputBorder(
          borderRadius: control,
          borderSide: hairline,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: control,
          borderSide: hairline,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: control,
          borderSide: BorderSide(color: scheme.primary, width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: control,
          borderSide: BorderSide(color: scheme.error, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: control,
          borderSide: BorderSide(color: scheme.error, width: 1.4),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          disabledBackgroundColor: ramp.raisedHigh,
          disabledForegroundColor: ramp.textMuted,
          elevation: 0,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.x4,
            vertical: AppSpace.x3,
          ),
          minimumSize: const Size(0, 40),
          shape: RoundedRectangleBorder(borderRadius: control),
          textStyle: text.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.x3,
            vertical: AppSpace.x2,
          ),
          minimumSize: const Size(0, 36),
          shape: RoundedRectangleBorder(borderRadius: control),
          textStyle: text.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: ramp.text,
          side: hairline,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.x4,
            vertical: AppSpace.x3,
          ),
          minimumSize: const Size(0, 40),
          shape: RoundedRectangleBorder(borderRadius: control),
          textStyle: text.labelLarge,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: ramp.textDim,
          highlightColor: ramp.text.withValues(alpha: 0.04),
          shape: RoundedRectangleBorder(borderRadius: control),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: ramp.raised,
        selectedColor: ramp.raisedHigh,
        side: hairline,
        labelStyle: text.labelMedium,
        secondaryLabelStyle: text.labelMedium?.copyWith(color: ramp.textDim),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.x2 + 2,
          vertical: AppSpace.x1 + 2,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.control - 2),
        ),
        showCheckmark: false,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: ramp.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: card, side: hairline),
        textStyle: text.bodyMedium,
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll<Color>(ramp.surface),
          surfaceTintColor: const WidgetStatePropertyAll<Color>(
            Colors.transparent,
          ),
          elevation: const WidgetStatePropertyAll<double>(0),
          shape: WidgetStatePropertyAll<OutlinedBorder>(
            RoundedRectangleBorder(borderRadius: card, side: hairline),
          ),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith<Color>((states) {
          if (states.contains(WidgetState.selected)) {
            return scheme.onPrimary;
          }
          return ramp.textMuted;
        }),
        trackColor: WidgetStateProperty.resolveWith<Color>((states) {
          if (states.contains(WidgetState.selected)) {
            return scheme.primary;
          }
          return ramp.raisedHigh;
        }),
        trackOutlineColor: WidgetStateProperty.resolveWith<Color>((states) {
          if (states.contains(WidgetState.selected)) {
            return Colors.transparent;
          }
          return ramp.border;
        }),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: scheme.primary,
        inactiveTrackColor: ramp.raisedHigh,
        thumbColor: scheme.primary,
        overlayColor: scheme.primary.withValues(alpha: 0.12),
        trackHeight: 2,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: ramp.raisedHigh,
        circularTrackColor: ramp.raisedHigh,
        linearMinHeight: 2,
      ),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 500),
        decoration: BoxDecoration(
          color: scheme.inverseSurface,
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: text.bodySmall?.copyWith(color: scheme.onInverseSurface),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: scheme.primary,
        selectionColor: scheme.primary.withValues(alpha: 0.24),
        selectionHandleColor: scheme.primary,
      ),
      scrollbarTheme: ScrollbarThemeData(
        thickness: const WidgetStatePropertyAll<double>(3),
        radius: const Radius.circular(2),
        thumbColor: WidgetStatePropertyAll<Color>(
          ramp.textMuted.withValues(alpha: 0.4),
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: ramp.background,
        selectedItemColor: ramp.text,
        unselectedItemColor: ramp.textMuted,
        elevation: 0,
        type: BottomNavigationBarType.fixed,
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: ramp.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        width: 300,
        shape: const RoundedRectangleBorder(),
      ),
    );
  }
}
