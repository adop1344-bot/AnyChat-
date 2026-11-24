import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/errors/debug_log.dart';
import '../../../core/storage/token_estimator.dart';
import '../../../core/theme/accent_colors.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/tools/termux_shell.dart';
import '../../../core/ui/atoms.dart';
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
                          return Padding(
                            padding: const EdgeInsets.only(
                              bottom: AppSpace.x3,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  DateFormat('dd.MM HH:mm:ss')
                                      .format(entry.time),
                                  style: AppType.figure(
                                    10.5,
                                    color: Theme.of(ctx)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                                ),
                                Text(
                                  entry.raw,
                                  maxLines: 6,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppType.figure(11),
                                ),
                              ],
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
                  child: Text(l10n.closeButton),
                ),
              ],
            );
          },
        );
      },
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
    final effortValue =
        efforts.contains(settings.reasoningEffort) ? settings.reasoningEffort : '';

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: AppSpace.x10),
        children: <Widget>[
          _ConnectionCard(
            providerName: provider?.name ?? l10n.errNoProvider,
            format: provider?.format.name ?? '—',
            modelId: settings.selectedModelId ?? l10n.modelNotSelected,
            contextWindow: settings.modelContextWindow,
            onProviders: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (BuildContext routeContext) => const ProvidersScreen(),
              ),
            ),
            onModels: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (BuildContext routeContext) => const ModelsScreen(),
              ),
            ),
          ),
          _Group(
            label: l10n.generateSection,
            children: <Widget>[
              _SwitchRow(
                title: 'Уведомление при генерации',
                hint: 'Android не выгружает приложение, пока идёт ответ',
                value: settings.keepAlive,
                onChanged: (bool value) => _controller.setKeepAlive(value),
              ),
              _FieldRow(
                label: l10n.maxTokensLabel,
                hint: l10n.maxTokensHint,
                controller: _maxTokensController,
                onChanged: _onMaxTokensChanged,
                placeholder: 'авто',
              ),
              _FieldRow(
                label: l10n.timeoutLabel,
                controller: _timeoutController,
                onChanged: _onTimeoutChanged,
                placeholder: '90',
              ),
              _PromptRow(
                label: l10n.systemPromptLabel,
                hint: l10n.systemPromptHint,
                controller: _systemPromptController,
                onChanged: (String value) => _controller.setSystemPrompt(value),
              ),
            ],
          ),
          _Group(
            label: l10n.advancedSettings,
            children: <Widget>[
              if (efforts.isNotEmpty)
                _DropdownRow<String>(
                  label: 'reasoning_effort',
                  value: effortValue,
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
              _SwitchRow(
                title: l10n.promptCachingLabel,
                hint: l10n.promptCachingSubtitle,
                value: settings.promptCaching,
                onChanged: (bool value) => _controller.setPromptCaching(value),
              ),
              _SwitchRow(
                title: 'Поиск в интернете',
                hint: 'DuckDuckGo и чтение страниц во время ответа',
                value: settings.webSearch,
                onChanged: (bool value) => _controller.setWebSearch(value),
              ),
              _SwitchRow(
                title: 'Терминал (Termux)',
                hint: 'Модель выполняет команды на телефоне через RUN:',
                value: settings.agentShell,
                onChanged: (bool value) => _controller.setAgentShell(value),
              ),
              _ActionRow(
                title: 'Проверить Termux',
                hint: 'Запускает echo через RUN_COMMAND',
                icon: Icons.play_arrow_rounded,
                onTap: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  String msg;
                  if (!await TermuxShell.available()) {
                    msg = 'Termux не найден — установи Termux';
                  } else {
                    msg = (await TermuxShell.run('echo ok'))
                        .replaceAll('\n', ' ');
                    if (msg.length > 90) msg = msg.substring(0, 90);
                  }
                  messenger.showSnackBar(SnackBar(content: Text(msg)));
                },
              ),
              _FieldRow(
                label: l10n.contextLimitLabel,
                hint: l10n.contextLimitHint,
                controller: _contextLimitController,
                onChanged: _onContextLimitChanged,
                placeholder: 'авто',
              ),
              _FieldRow(
                label: l10n.historyDepthLabel,
                hint: l10n.historyDepthHint,
                controller: _historyDepthController,
                onChanged: _onHistoryDepthChanged,
                placeholder: 'все',
              ),
            ],
          ),
          _Group(
            label: l10n.appearanceSection,
            children: <Widget>[
              _DropdownRow<String>(
                label: l10n.language,
                value: settings.localeCode ?? 'auto',
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
              _DropdownRow<String>(
                label: l10n.themeMode,
                value: settings.themeMode,
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
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpace.x4,
                  AppSpace.x3,
                  AppSpace.x4,
                  AppSpace.x4,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Text(
                          l10n.accentColor,
                          style: theme.textTheme.bodyMedium,
                        ),
                        const Spacer(),
                        Text(
                          settings.accentColor == 'system'
                              ? 'из обоев'
                              : _accentLabel(l10n, settings.accentColor),
                          style: AppType.figure(
                            11,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpace.x3),
                    Wrap(
                      spacing: AppSpace.x3,
                      runSpacing: AppSpace.x3,
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
          _Group(
            label: l10n.debugLog,
            children: <Widget>[
              _ActionRow(
                title: l10n.debugLog,
                hint: 'Запросы, ответы и ошибки провайдера',
                icon: Icons.chevron_right,
                onTap: _showDebugLog,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _accentSwatch({
    required String key,
    required String label,
    required Color? color,
    required bool selected,
  }) {
    final theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;
    final Color? tint = color;
    final Color check = tint == null
        ? theme.colorScheme.primary
        : (tint.computeLuminance() > 0.5
            ? const Color(0xFF14161A)
            : const Color(0xFFFFFFFF));
    return Tooltip(
      message: label,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.control - 2),
        onTap: () => _controller.setAccentColor(key),
        child: AnimatedContainer(
          duration: AppMotion.fast,
          curve: AppMotion.curve,
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: tint ??
                (isDark
                    ? theme.colorScheme.surfaceContainerHigh
                    : theme.colorScheme.surfaceContainer),
            borderRadius: BorderRadius.circular(AppRadius.control - 2),
            border: Border.all(
              color: selected
                  ? theme.colorScheme.onSurface
                  : theme.colorScheme.outlineVariant,
              width: selected ? 2 : 1,
            ),
          ),
          child: tint == null
              ? Icon(
                  Icons.brightness_auto_outlined,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                )
              : (selected ? Icon(Icons.check, size: 18, color: check) : null),
        ),
      ),
    );
  }
}

/// Where the app is pointed at: provider, format and the model in use, as one
/// block. Two tappable halves, no settings rows wasted on the same facts.
class _ConnectionCard extends StatelessWidget {
  const _ConnectionCard({
    required this.providerName,
    required this.format,
    required this.modelId,
    required this.contextWindow,
    required this.onProviders,
    required this.onModels,
  });

  final String providerName;
  final String format;
  final String modelId;
  final int? contextWindow;
  final VoidCallback onProviders;
  final VoidCallback onModels;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppSpace.x4,
        AppSpace.x2,
        AppSpace.x4,
        0,
      ),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        children: <Widget>[
          InkWell(
            onTap: onProviders,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(AppRadius.card - 1),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.x4,
                AppSpace.x3,
                AppSpace.x3,
                AppSpace.x3,
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          providerName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: <Widget>[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: scheme.surfaceContainerHigh,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                format,
                                style: AppType.figure(
                                  10,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                            const SizedBox(width: AppSpace.x2),
                            StatusDot(color: scheme.primary, size: 5),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          Hairline(color: scheme.outlineVariant),
          InkWell(
            onTap: onModels,
            borderRadius: const BorderRadius.vertical(
              bottom: Radius.circular(AppRadius.card - 1),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.x4,
                AppSpace.x3,
                AppSpace.x3,
                AppSpace.x3,
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      modelId,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.figure(
                        14,
                        weight: FontWeight.w500,
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
                  if (contextWindow != null) ...<Widget>[
                    Figure(
                      '${formatTokenCount(contextWindow!)} ctx',
                      size: 10.5,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: AppSpace.x2),
                  ],
                  Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A titled group: quiet label, one surface, rows split by hairlines.
class _Group extends StatelessWidget {
  const _Group({required this.label, required this.children});

  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<Widget> rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      rows.add(children[i]);
      if (i != children.length - 1) {
        rows.add(
          Padding(
            padding: const EdgeInsets.only(left: AppSpace.x4),
            child: Hairline(color: theme.colorScheme.outlineVariant),
          ),
        );
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SectionLabel(label),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: AppSpace.x4),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(children: rows),
        ),
      ],
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.title,
    required this.value,
    required this.onChanged,
    this.hint,
  });

  final String title;
  final String? hint;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return InkWell(
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpace.x4,
          AppSpace.x3 - 2,
          AppSpace.x2,
          AppSpace.x3 - 2,
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(title, style: theme.textTheme.bodyMedium),
                  if (hint != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Text(
                        hint!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: AppSpace.x2),
            Switch(value: value, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}

/// Label on the left, the number itself on the right in mono. Tapping the row
/// focuses the field, so the whole line is the target.
class _FieldRow extends StatefulWidget {
  const _FieldRow({
    required this.label,
    required this.controller,
    required this.onChanged,
    this.hint,
    this.placeholder,
  });

  final String label;
  final String? hint;
  final String? placeholder;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  State<_FieldRow> createState() => _FieldRowState();
}

class _FieldRowState extends State<_FieldRow> {
  final FocusNode _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return InkWell(
      onTap: _focus.requestFocus,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpace.x4,
          AppSpace.x2,
          AppSpace.x4,
          AppSpace.x2,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(widget.label, style: theme.textTheme.bodyMedium),
                  if (widget.hint != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Text(
                        widget.hint!,
                        maxLines: 2,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: AppSpace.x3),
            SizedBox(
              width: 96,
              child: TextField(
                controller: widget.controller,
                focusNode: _focus,
                onChanged: widget.onChanged,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.right,
                style: AppType.figure(
                  13.5,
                  weight: FontWeight.w500,
                  color: scheme.onSurface,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  filled: false,
                  hintText: widget.placeholder,
                  hintStyle: AppType.figure(
                    13.5,
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
                  ),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 6),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PromptRow extends StatelessWidget {
  const _PromptRow({
    required this.label,
    required this.controller,
    required this.onChanged,
    this.hint,
  });

  final String label;
  final String? hint;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.x4,
        AppSpace.x3,
        AppSpace.x4,
        AppSpace.x3,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label, style: theme.textTheme.bodyMedium),
          const SizedBox(height: AppSpace.x2),
          TextField(
            controller: controller,
            onChanged: onChanged,
            minLines: 2,
            maxLines: 6,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurface,
              height: 1.5,
            ),
            decoration: InputDecoration(
              isDense: true,
              hintText: hint,
              hintStyle: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
              ),
              fillColor: scheme.surfaceContainerHigh,
              contentPadding: const EdgeInsets.all(AppSpace.x3),
            ),
          ),
        ],
      ),
    );
  }
}

class _DropdownRow<T> extends StatelessWidget {
  const _DropdownRow({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String label;
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.x4,
        AppSpace.x2,
        AppSpace.x3,
        AppSpace.x2,
      ),
      child: Row(
        children: <Widget>[
          Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
          DropdownButton<T>(
            value: value,
            items: items,
            onChanged: onChanged,
            underline: const SizedBox.shrink(),
            isDense: true,
            borderRadius: BorderRadius.circular(AppRadius.control),
            style: theme.textTheme.bodyMedium,
            icon: Icon(
              Icons.unfold_more,
              size: 16,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.title,
    required this.icon,
    required this.onTap,
    this.hint,
  });

  final String title;
  final String? hint;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpace.x4,
          AppSpace.x3,
          AppSpace.x3,
          AppSpace.x3,
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(title, style: theme.textTheme.bodyMedium),
                  if (hint != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Text(
                        hint!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Icon(
              icon,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}
