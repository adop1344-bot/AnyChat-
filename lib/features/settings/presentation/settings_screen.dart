import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/errors/debug_log.dart';
import '../../../core/theme/accent_colors.dart';
import '../../../l10n/app_localizations.dart';
import '../../models/presentation/models_screen.dart';
import '../../providers/domain/custom_provider.dart';
import '../../providers/domain/model_info.dart';
import '../../providers/presentation/providers_screen.dart';
import '../../providers/state/providers_state.dart';
import '../app_settings.dart';
import '../state/settings_controller.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final TextEditingController _maxTokensController = TextEditingController();
  final TextEditingController _timeoutController =
      TextEditingController(text: '90');
  final TextEditingController _systemPromptController =
      TextEditingController();
  final TextEditingController _contextLimitController =
      TextEditingController();
  final TextEditingController _historyDepthController =
      TextEditingController();
  bool _synced = false;

  @override
  void dispose() {
    _maxTokensController.dispose();
    _timeoutController.dispose();
    _systemPromptController.dispose();
    _contextLimitController.dispose();
    _historyDepthController.dispose();
    super.dispose();
  }

  void _syncFromSettings(AppSettings settings) {
    _synced = true;
    _maxTokensController.text = settings.maxTokens?.toString() ?? '';
    _timeoutController.text = settings.timeoutSeconds.toString();
    _systemPromptController.text = settings.systemPrompt;
    _contextLimitController.text = settings.contextLimit?.toString() ?? '';
    _historyDepthController.text = settings.historyDepth?.toString() ?? '';
  }

  SettingsController get _controller =>
      ref.read(settingsControllerProvider.notifier);

  void _onMaxTokensChanged(String value) {
    final parsed = int.tryParse(value.trim());
    if (value.trim().isEmpty) {
      _controller.setMaxTokens(null);
      return;
    }
    if (parsed != null && parsed > 0) {
      _controller.setMaxTokens(parsed);
    }
  }

  void _onTimeoutChanged(String value) {
    final parsed = int.tryParse(value.trim());
    if (parsed == null || parsed <= 0) return;
    final clamped = parsed < 1 ? 1 : (parsed > 600 ? 600 : parsed);
    _controller.setTimeoutSeconds(clamped);
  }

  String _accentLabel(AppLocalizations l10n, String key) {
    switch (key) {
      case 'black':
        return l10n.accentBlack;
      case 'blue':
        return l10n.accentBlue;
      case 'lightBlue':
        return l10n.accentLightBlue;
      case 'green':
        return l10n.accentGreen;
      case 'pink':
        return l10n.accentPink;
      case 'red':
        return l10n.accentRed;
      case 'orange':
        return l10n.accentOrange;
      case 'purple':
        return l10n.accentPurple;
      default:
        return key;
    }
  }

  void _onContextLimitChanged(String value) {
    final raw = value.trim();
    if (raw.isEmpty) {
      _controller.setContextLimit(null);
      return;
    }
    final parsed = int.tryParse(raw);
    if (parsed != null && parsed >= 1) {
      _controller.setContextLimit(parsed);
    }
  }

  void _onHistoryDepthChanged(String value) {
    final raw = value.trim();
    if (raw.isEmpty) {
      _controller.setHistoryDepth(null);
      return;
    }
    final parsed = int.tryParse(raw);
    if (parsed != null && parsed >= 1) {
      _controller.setHistoryDepth(parsed);
    }
  }

  Future<void> _showDebugLog() async {
    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        final l10n = AppLocalizations.of(dialogContext);
        return Consumer(
          builder: (BuildContext ctx, WidgetRef refs, Widget? child) {
            final entries = refs.watch(debugLogProvider);
            final reversed = entries.reversed.toList();
            return AlertDialog(
              title: Text(l10n.debugLog),
              content: SizedBox(
                width: double.maxFinite,
                height: 320,
                child: entries.isEmpty
                    ? Center(child: Text(l10n.debugLogEmpty))
                    : ListView.builder(
                        itemCount: reversed.length,
                        itemBuilder: (BuildContext itemContext, int index) {
                          final entry = reversed[index];
                          return ListTile(
                            dense: true,
                            title: Text(
                              entry.raw,
                              maxLines: 6,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              DateFormat('dd.MM.yyyy HH:mm:ss')
                                  .format(entry.time),
                            ),
                          );
                        },
                      ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => refs.read(debugLogProvider.notifier).clear(),
                  child: Text(l10n.clearLog),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: Text(l10n.cancel),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _accentSwatch({
    required String key,
    required String label,
    required Color? color,
    required bool selected,
  }) {
    final theme = Theme.of(context);
    return Tooltip(
      message: label,
      child: InkWell(
        borderRadius: BorderRadius.circular(26),
        onTap: () => _controller.setAccentColor(key),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color ?? theme.colorScheme.surfaceContainerHighest,
            border: Border.all(
              color: selected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outlineVariant,
              width: selected ? 3 : 1,
            ),
          ),
          child: color == null
              ? Icon(
                  Icons.auto_awesome,
                  size: 20,
                  color: theme.colorScheme.primary,
                )
              : null,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final loaded = ref.watch(settingsControllerProvider).when(
          data: (AppSettings value) => value,
          loading: () => null,
          error: (Object error, StackTrace stack) => null,
        );
    if (loaded != null && !_synced) {
      _syncFromSettings(loaded);
    }
    final settings = loaded ?? const AppSettings();
    final providers = ref.watch(customProvidersProvider).when(
          data: (List<CustomProvider> value) => value,
          loading: () => const <CustomProvider>[],
          error: (Object error, StackTrace stack) => const <CustomProvider>[],
        );
    CustomProvider? provider;
    for (final candidate in providers) {
      if (candidate.id == settings.selectedProviderId) {
        provider = candidate;
      }
    }
    var efforts = settings.modelReasoningEfforts;
    if (efforts.isEmpty && isReasoningModel(settings.selectedModelId ?? '')) {
      efforts = const <String>['low', 'medium', 'high'];
    }
    final effortValue = efforts.contains(settings.reasoningEffort)
        ? settings.reasoningEffort
        : '';

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: <Widget>[
          _section(
            context,
            l10n.providerSection,
            <Widget>[
              ListTile(
                title: Text(l10n.providersTitle),
                subtitle: Text(provider?.name ?? l10n.errNoProvider),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (BuildContext routeContext) =>
                        const ProvidersScreen(),
                  ),
                ),
              ),
            ],
          ),
          _section(
            context,
            l10n.modelsTitle,
            <Widget>[
              ListTile(
                leading: const Icon(Icons.auto_awesome_outlined),
                title: Text(
                  settings.selectedModelId ?? l10n.modelNotSelected,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(provider?.name ?? l10n.errNoProvider),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (BuildContext routeContext) =>
                        const ModelsScreen(),
                  ),
                ),
              ),
            ],
          ),
          _section(
            context,
            l10n.generateSection,
            <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: TextField(
                  controller: _maxTokensController,
                  keyboardType: TextInputType.number,
                  onChanged: _onMaxTokensChanged,
                  decoration: InputDecoration(
                    labelText: l10n.maxTokensLabel,
                    helperText: l10n.maxTokensHint,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                child: TextField(
                  controller: _timeoutController,
                  keyboardType: TextInputType.number,
                  onChanged: _onTimeoutChanged,
                  decoration: InputDecoration(
                    labelText: l10n.timeoutLabel,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                child: TextField(
                  controller: _systemPromptController,
                  minLines: 2,
                  maxLines: 6,
                  onChanged: (String value) =>
                      _controller.setSystemPrompt(value),
                  decoration: InputDecoration(
                    labelText: l10n.systemPromptLabel,
                    helperText: l10n.systemPromptHint,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                ),
              ),
            ],
          ),
          _section(
            context,
            l10n.advancedSettings,
            <Widget>[
              if (efforts.isNotEmpty)
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  title: const Text('reasoning_effort'),
                  trailing: DropdownButton<String>(
                    value: effortValue,
                    underline: const SizedBox.shrink(),
                    items: <DropdownMenuItem<String>>[
                      DropdownMenuItem<String>(
                        value: '',
                        child: Text(l10n.reasoningOff),
                      ),
                      for (final String level in efforts)
                        DropdownMenuItem<String>(
                          value: level,
                          child: Text(level),
                        ),
                    ],
                    onChanged: (String? value) {
                      if (value == null) return;
                      _controller.setReasoningEffort(value);
                    },
                  ),
                ),
              SwitchListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                title: Text(l10n.promptCachingLabel),
                subtitle: Text(l10n.promptCachingSubtitle),
                value: settings.promptCaching,
                onChanged: (bool value) =>
                    _controller.setPromptCaching(value),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: TextField(
                  controller: _contextLimitController,
                  keyboardType: TextInputType.number,
                  onChanged: _onContextLimitChanged,
                  decoration: InputDecoration(
                    labelText: l10n.contextLimitLabel,
                    helperText: l10n.contextLimitHint,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                child: TextField(
                  controller: _historyDepthController,
                  keyboardType: TextInputType.number,
                  onChanged: _onHistoryDepthChanged,
                  decoration: InputDecoration(
                    labelText: l10n.historyDepthLabel,
                    helperText: l10n.historyDepthHint,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                ),
              ),
            ],
          ),
          _section(
            context,
            l10n.appearanceSection,
            <Widget>[
              ListTile(
                title: Text(l10n.language),
                trailing: DropdownButton<String>(
                  value: settings.localeCode ?? 'auto',
                  underline: const SizedBox.shrink(),
                  items: <DropdownMenuItem<String>>[
                    DropdownMenuItem<String>(
                      value: 'auto',
                      child: Text(l10n.langAuto),
                    ),
                    const DropdownMenuItem<String>(
                      value: 'en',
                      child: Text('English'),
                    ),
                    const DropdownMenuItem<String>(
                      value: 'ru',
                      child: Text('Русский'),
                    ),
                    const DropdownMenuItem<String>(
                      value: 'uk',
                      child: Text('Українська'),
                    ),
                  ],
                  onChanged: (String? value) =>
                      _controller.setLocale(value == 'auto' ? null : value),
                ),
              ),
              ListTile(
                title: Text(l10n.themeMode),
                trailing: DropdownButton<String>(
                  value: settings.themeMode,
                  underline: const SizedBox.shrink(),
                  items: <DropdownMenuItem<String>>[
                    DropdownMenuItem<String>(
                      value: 'system',
                      child: Text(l10n.themeSystem),
                    ),
                    DropdownMenuItem<String>(
                      value: 'light',
                      child: Text(l10n.themeLight),
                    ),
                    DropdownMenuItem<String>(
                      value: 'dark',
                      child: Text(l10n.themeDark),
                    ),
                  ],
                  onChanged: (String? value) {
                    if (value == null) return;
                    _controller.setThemeMode(value);
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      l10n.accentColor,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: <Widget>[
                        _accentSwatch(
                          key: 'system',
                          label: l10n.themeSystem,
                          color: null,
                          selected: settings.accentColor == 'system',
                        ),
                        for (final MapEntry<String, Color> entry
                            in kAccentColors.entries)
                          _accentSwatch(
                            key: entry.key,
                            label: _accentLabel(l10n, entry.key),
                            color: entry.value,
                            selected: settings.accentColor == entry.key,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          _section(
            context,
            l10n.debugLog,
            <Widget>[
              ListTile(
                title: Text(l10n.debugLog),
                leading: const Icon(Icons.bug_report_outlined),
                trailing: const Icon(Icons.chevron_right),
                onTap: _showDebugLog,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _section(BuildContext context, String title, List<Widget> children) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Column(children: children),
            ),
          ),
        ],
      ),
    );
  }
}
