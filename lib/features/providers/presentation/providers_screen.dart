import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app_providers.dart';
import '../../../core/errors/api_error.dart';
import '../../../core/errors/debug_log.dart';
import '../../../core/errors/error_localizer.dart';
import '../../../core/network/api_format.dart';
import '../../../core/storage/secure_storage.dart';
import '../../../l10n/app_localizations.dart';
import '../../settings/state/settings_controller.dart';
import '../data/provider_adapter.dart';
import '../domain/custom_provider.dart';
import '../state/providers_state.dart';

class ProvidersScreen extends ConsumerWidget {
  const ProvidersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final selectedId = ref.watch(settingsControllerProvider).when(
          data: (value) => value.selectedProviderId,
          loading: () => '',
          error: (Object error, StackTrace stack) => '',
        );
    final providersAsync = ref.watch(customProvidersProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.providersTitle),
        actions: <Widget>[
          IconButton(
            tooltip: l10n.refreshHealth,
            icon: const Icon(Icons.refresh),
            onPressed: () {
              providersAsync.whenData((List<CustomProvider> providers) {
                for (final provider in providers) {
                  ref.invalidate(providerHealthProvider(provider.id));
                }
              });
            },
          ),
          IconButton(
            tooltip: l10n.addProvider,
            icon: const Icon(Icons.add),
            onPressed: () => _showEditor(ref, context),
          ),
        ],
      ),
      body: providersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace stack) =>
            Center(child: Text(l10n.errUnknown('$error'))),
        data: (List<CustomProvider> providers) {
          if (providers.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(l10n.noProvidersYet, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: () => _showEditor(ref, context),
                      icon: const Icon(Icons.add),
                      label: Text(l10n.addProvider),
                    ),
                  ],
                ),
              ),
            );
          }
          return ListView.separated(
            itemCount: providers.length,
            separatorBuilder: (BuildContext ctx, int index) =>
                const Divider(height: 1),
            itemBuilder: (BuildContext ctx, int index) {
              final provider = providers[index];
              return ListTile(
                leading: Icon(
                  selectedId == provider.id
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                ),
                title: Text(provider.name),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('${provider.baseUrl} · ${provider.format.name}'),
                    const SizedBox(height: 2),
                    _HealthBadge(providerId: provider.id),
                  ],
                ),
                selected: selectedId == provider.id,
                onTap: () => ref
                    .read(settingsControllerProvider.notifier)
                    .selectProvider(provider.id),
                trailing: PopupMenuButton<String>(
                  onSelected: (String value) {
                    switch (value) {
                      case 'edit':
                        _showEditor(ref, context, existing: provider);
                      case 'check':
                        _checkProvider(ref, context, provider);
                      case 'delete':
                        _deleteProvider(ref, context, provider);
                    }
                  },
                  itemBuilder: (BuildContext menuContext) =>
                      <PopupMenuEntry<String>>[
                    PopupMenuItem<String>(
                      value: 'edit',
                      child: Text(l10n.editProvider),
                    ),
                    PopupMenuItem<String>(
                      value: 'check',
                      child: Text(l10n.checkKey),
                    ),
                    PopupMenuItem<String>(
                      value: 'delete',
                      child: Text(l10n.deleteProvider),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _snack(BuildContext context, String message) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _showEditor(
    WidgetRef ref,
    BuildContext context, {
    CustomProvider? existing,
  }) {
    return showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) =>
          _ProviderEditor(existing: existing),
    );
  }

  Future<void> _checkProvider(
    WidgetRef ref,
    BuildContext context,
    CustomProvider provider,
  ) async {
    final l10n = AppLocalizations.of(context);
    final key = await ref.read(keyStoreProvider).readKey(provider.id);
    final apiKey = (key ?? '').trim();
    if (apiKey.isEmpty) {
      if (!context.mounted) return;
      _snack(context, l10n.keyMissing);
      return;
    }

    final settings = await ref.read(settingsControllerProvider.future);
    String? model;
    if (settings.selectedProviderId == provider.id) {
      model = settings.selectedModelId;
    }
    if (model == null || model.trim().isEmpty) {
      try {
        final models = await adapterFor(provider.format).fetchModels(
          apiKey: apiKey,
          baseUrl: provider.baseUrl,
        );
        model = models.isEmpty ? null : models.first.id;
      } catch (_) {
        model = null;
      }
    }
    if (model == null || model.trim().isEmpty) {
      if (!context.mounted) return;
      _snack(context, l10n.errNoModel);
      return;
    }

    if (!context.mounted) return;
    final probe = ChatParams(
      apiKey: apiKey,
      baseUrl: provider.baseUrl,
      model: model,
      turns: const <ChatTurn>[
        ChatTurn(role: 'user', content: 'ping'),
      ],
      maxTokens: 32,
      timeout: const Duration(seconds: 60),
    );
    try {
      await for (final _ in adapterFor(provider.format).streamChat(probe)) {
        // Drain: a completed request proves the key works.
      }
      if (!context.mounted) return;
      _snack(context, l10n.keyOk);
    } catch (e) {
      if (!context.mounted) return;
      if (e is ApiError) {
        ref.read(debugLogProvider.notifier).add(e);
        _snack(context, localizeApiError(l10n, e));
      } else {
        _snack(context, l10n.errUnknown('$e'));
      }
    }
  }

  Future<void> _deleteProvider(
    WidgetRef ref,
    BuildContext context,
    CustomProvider provider,
  ) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(l10n.deleteProvider),
        content: Text(provider.name),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await ref.read(keyStoreProvider).deleteKey(provider.id);
    await ref
        .read(providerConfigRepositoryProvider)
        .deleteProvider(provider.id);
    ref.invalidate(hasApiKeyProvider(provider.id));
    ref.invalidate(providerModelsProvider(provider.id));
    if (!context.mounted) return;
    final settings = await ref.read(settingsControllerProvider.future);
    if (settings.selectedProviderId == provider.id) {
      await ref
          .read(settingsControllerProvider.notifier)
          .selectProvider('');
    }
  }
}

class _ProviderEditor extends ConsumerStatefulWidget {
  const _ProviderEditor({this.existing});

  final CustomProvider? existing;

  @override
  ConsumerState<_ProviderEditor> createState() => _ProviderEditorState();
}

class _ProviderEditorState extends ConsumerState<_ProviderEditor> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _urlController;
  final TextEditingController _keyController = TextEditingController();
  ApiFormat _format = ApiFormat.openai;
  bool _hasKey = false;
  String? _keyMask;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _nameController = TextEditingController(text: existing?.name ?? '');
    _urlController = TextEditingController(text: existing?.baseUrl ?? '');
    if (existing != null) {
      _format = existing.format;
      _loadKeyState(existing.id);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    _keyController.dispose();
    super.dispose();
  }

  Future<void> _loadKeyState(String providerId) async {
    final key = await ref.read(keyStoreProvider).readKey(providerId);
    if (!mounted) return;
    final trimmed = (key ?? '').trim();
    setState(() {
      _hasKey = trimmed.isNotEmpty;
      _keyMask =
          trimmed.isEmpty ? null : SecureKeyStore.maskKey(trimmed);
    });
  }

  String? _validateUrl(String? value) {
    final l10n = AppLocalizations.of(context);
    final raw = (value ?? '').trim();
    if (raw.isEmpty) return l10n.endpointLabel;
    final uri = Uri.tryParse(raw);
    if (uri == null ||
        !uri.hasScheme ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      return l10n.endpointLabel;
    }
    return null;
  }

  Future<void> _save() async {
    final formState = _formKey.currentState;
    if (formState == null || !formState.validate()) return;
    final existing = widget.existing;
    final name = _nameController.text.trim();
    final url = _urlController.text.trim();
    final key = _keyController.text.trim();
    final repo = ref.read(providerConfigRepositoryProvider);

    if (existing == null) {
      final created = await repo.create(
        name: name,
        baseUrl: url,
        format: _format,
      );
      if (key.isNotEmpty) {
        await ref.read(keyStoreProvider).writeKey(created.id, key);
      }
      ref.invalidate(hasApiKeyProvider(created.id));
      ref.invalidate(providerModelsProvider(created.id));
      if (!mounted) return;
      await ref
          .read(settingsControllerProvider.notifier)
          .selectProvider(created.id);
    } else {
      await repo.updateProvider(
        existing.id,
        name: name,
        baseUrl: url,
        format: _format,
      );
      if (key.isNotEmpty) {
        await ref.read(keyStoreProvider).writeKey(existing.id, key);
        ref.invalidate(hasApiKeyProvider(existing.id));
      }
      ref.invalidate(providerModelsProvider(existing.id));
    }
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isEdit = widget.existing != null;
    final mask = _keyMask;

    return AlertDialog(
      title: Text(isEdit ? l10n.editProvider : l10n.addProvider),
      content: SizedBox(
        width: double.maxFinite,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              TextFormField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: l10n.providerNameLabel,
                  isDense: true,
                ),
                validator: (String? value) =>
                    (value == null || value.trim().isEmpty)
                        ? l10n.providerNameLabel
                        : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _urlController,
                keyboardType: TextInputType.url,
                decoration: InputDecoration(
                  labelText: l10n.endpointLabel,
                  hintText: 'https://api.example.com/v1',
                  isDense: true,
                ),
                validator: _validateUrl,
              ),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  Text(
                    l10n.formatLabel,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButton<ApiFormat>(
                      value: _format,
                      isExpanded: true,
                      underline: const SizedBox.shrink(),
                      items: const <DropdownMenuItem<ApiFormat>>[
                        DropdownMenuItem<ApiFormat>(
                          value: ApiFormat.openai,
                          child: Text('openai'),
                        ),
                        DropdownMenuItem<ApiFormat>(
                          value: ApiFormat.anthropic,
                          child: Text('anthropic'),
                        ),
                        DropdownMenuItem<ApiFormat>(
                          value: ApiFormat.gemini,
                          child: Text('gemini'),
                        ),
                      ],
                      onChanged: (ApiFormat? value) {
                        if (value == null) return;
                        setState(() => _format = value);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _keyController,
                obscureText: true,
                enableSuggestions: false,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: l10n.apiKeyLabel,
                  hintText: 'sk-...',
                  isDense: true,
                  helperText: (isEdit && _hasKey && mask != null)
                      ? l10n.keySavedMasked(mask)
                      : null,
                ),
              ),
              if (isEdit) ...<Widget>[
                const SizedBox(height: 16),
                _ModelCheckSection(provider: widget.existing!),
              ],
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: _save,
          child: Text(isEdit ? l10n.save : l10n.saveKey),
        ),
      ],
    );
  }
}

class _HealthBadge extends ConsumerWidget {
  const _HealthBadge({required this.providerId});

  final String providerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final health = ref.watch(providerHealthProvider(providerId));
    final Color color;
    final String label;
    final value = health.value;
    if (health.hasError || (value != null && value.state == ProviderHealthState.down)) {
      color = const Color(0xFFE53935);
      label = l10n.providerHealthOffline;
    } else if (value == null) {
      color = Colors.grey;
      label = '…';
    } else {
      switch (value.state) {
        case ProviderHealthState.ok:
          color = const Color(0xFF43A047);
        case ProviderHealthState.reachable:
          color = const Color(0xFFFB8C00);
        case ProviderHealthState.down:
        case ProviderHealthState.unknown:
          color = Colors.grey;
      }
      label = value.state == ProviderHealthState.unknown
          ? l10n.providerHealthOffline
          : l10n.providerHealthMs(value.ms);
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _ModelCheckSection extends ConsumerStatefulWidget {
  const _ModelCheckSection({required this.provider});

  final CustomProvider provider;

  @override
  ConsumerState<_ModelCheckSection> createState() =>
      _ModelCheckSectionState();
}

class _ModelCheckSectionState extends ConsumerState<_ModelCheckSection> {
  bool _running = false;
  ModelCheckProgress? _progress;
  String? _summary;
  String? _error;

  Future<void> _run() async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _running = true;
      _progress = null;
      _summary = null;
      _error = null;
    });
    try {
      final summary = await checkAllProviderModels(
        ref.read(providerConfigRepositoryProvider),
        ref.read(keyStoreProvider),
        widget.provider,
        onProgress: (ModelCheckProgress progress) {
          if (mounted) setState(() => _progress = progress);
        },
      );
      ref.invalidate(providerModelsProvider(widget.provider.id));
      ref.invalidate(hiddenModelCountProvider(widget.provider.id));
      if (!mounted) return;
      setState(() {
        _running = false;
        _summary = l10n.checkDone(summary.ok, summary.failed);
      });
    } catch (Object error) {
      if (!mounted) return;
      setState(() {
        _running = false;
        _error = l10n.errUnknown('$error');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final progress = _progress;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _running ? null : _run,
            icon: _running
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.checklist),
            label: Text(l10n.checkAllModels),
          ),
        ),
        if (_running && progress != null) ...<Widget>[
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: progress.total == 0
                ? null
                : progress.tested / progress.total,
          ),
          const SizedBox(height: 4),
          Text(
            '${progress.tested}/${progress.total} · ${l10n.checkFailed(progress.failed)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        if (_summary != null) ...<Widget>[
          const SizedBox(height: 6),
          Text(
            _summary!,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.apply(color: scheme.primary),
          ),
        ],
        if (_error != null) ...<Widget>[
          const SizedBox(height: 6),
          Text(
            _error!,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.apply(color: scheme.error),
          ),
        ],
      ],
    );
  }
}
