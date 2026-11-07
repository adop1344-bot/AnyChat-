import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/accent_colors.dart';
import 'core/theme/app_theme.dart';
import 'features/home/main_shell.dart';
import 'features/settings/app_settings.dart';
import 'features/settings/state/settings_controller.dart';
import 'l10n/app_localizations.dart';

class AnyChatApp extends ConsumerWidget {
  const AnyChatApp({super.key});

  static const Color _seed = Color(0xFF6750A4);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(settingsControllerProvider);
    final settings = settingsAsync.when(
      data: (AppSettings value) => value,
      loading: () => const AppSettings(),
      error: (Object error, StackTrace stack) => const AppSettings(),
    );
    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) {
        final lightSeed = lightDynamic?.primary;
        final darkSeed = darkDynamic?.primary;
        return _buildApp(settings, lightSeed, darkSeed);
      },
    );
  }

  Widget _buildApp(
    AppSettings settings,
    Color? lightSeed,
    Color? darkSeed,
  ) {
    final manualAccent = kAccentColors[settings.accentColor];
    final fallback = manualAccent ?? _seed;
    final light =
        manualAccent?.harmonizeWith(lightSeed ?? fallback) ?? lightSeed ?? fallback;
    final dark =
        manualAccent?.harmonizeWith(darkSeed ?? fallback) ?? darkSeed ?? fallback;
    final localeCode = settings.localeCode;
    return MaterialApp(
      title: 'AnyChat+',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(light),
      darkTheme: AppTheme.dark(dark),
      themeMode: _themeMode(settings.themeMode),
      locale: localeCode == null ? null : Locale(localeCode),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: const MainShell(),
    );
  }

  static ThemeMode _themeMode(String value) {
    switch (value) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }
}
