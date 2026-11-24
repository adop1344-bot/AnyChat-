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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(settingsControllerProvider);
    final settings = settingsAsync.when(
      data: (AppSettings value) => value,
      loading: () => const AppSettings(),
      error: (Object error, StackTrace stack) => const AppSettings(),
    );
    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        return _buildApp(settings, lightDynamic, darkDynamic);
      },
    );
  }

  Widget _buildApp(
    AppSettings settings,
    ColorScheme? lightDynamic,
    ColorScheme? darkDynamic,
  ) {
    // A picked colour wins. Otherwise the wallpaper's primary is used as the
    // accent only - surfaces stay neutral either way.
    final Color? manual = kAccentColors[settings.accentColor];
    final Color lightAccent = manual ?? lightDynamic?.primary ?? kDefaultAccent;
    final Color darkAccent = manual ?? darkDynamic?.primary ?? kDefaultAccent;
    final String? localeCode = settings.localeCode;

    return MaterialApp(
      title: 'AnyChat+',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(lightAccent),
      darkTheme: AppTheme.dark(darkAccent),
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
