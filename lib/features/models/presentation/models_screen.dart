import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app_providers.dart';

import '../../../core/storage/token_estimator.dart';
import '../../../l10n/app_localizations.dart';
import '../../providers/domain/model_info.dart';
import '../../providers/domain/custom_provider.dart';
import '../../providers/presentation/providers_screen.dart';
import '../../providers/state/providers_state.dart';
import '../../settings/app_settings.dart';
import '../../settings/state/settings_controller.dart';

class ModelsScreen extends ConsumerStatefulWidget {
  const ModelsScreen({super.key});

  @override
  ConsumerState<ModelsScreen> createState() => _ModelsScreenState();
}

class _ModelsScreenState extends ConsumerState<ModelsScreen> {
  final TextEditingController _customController = TextEditingController();
  String _query = '';
  bool _checking = false;
  Map<String, bool> _liveStatuses = <String, bool>{};
  ModelCheckProgress? _checkProgress;
  String? _checkSummary;
  String? _checkError;

  @override
  void dispose() {
    _customController.dispose();
    super.dispose();
  }

  Future<void> _runCheck(CustomProvider provider) async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _checking = true;
      _liveStatuses = <String, bool>{};
      _checkProgress = null;
      _checkSummary = null;
      _checkError = null;
    });
    try {
      final summary = await checkAllProviderModels(
        ref.read(providerConfigRepositoryProvider),
        ref.read(keyStoreProvider),
        provider,
        onProgress: (ModelCheckProgress progress) {
          if (!mounted) return;
          setState(() {
            _checkProgress = progress;
            _liveStatuses = progress.statuses;
          });
        },
      );
      ref.invalidate(modelCheckStatusesProvider(provider.id));
      if (!mounted) return;
      setState(() {
        _checking = false;
        _checkSummary = l10n.checkDone(summary.ok, summary.failed);
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _checking = false;
        _checkError = l10n.errUnknown('$error');
      });
    }
  }

  void _applyCustomModel(String providerId) {
    final modelId = _customController.text.trim();
    if (modelId.isEmpty) return;
    ref
        .read(settingsControllerProvider.notifier)
        .selectModel(providerId: providerId, modelId: modelId);
    _customController.clear();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final settings = ref.watch(settingsControllerProvider).when(
          data: (AppSettings value) => value,
          loading: () => const AppSettings(),
          error: (Object error, StackTrace stack) => const AppSettings(),
        );
    final providers = ref.watch(customProvidersProvider).when(
          data: (List<CustomProvider> value) => value,
          loading: () => const <CustomProvider>[],
          error: (Object error, StackTrace stack) => const <CustomProvider>[],
        );
    CustomProvider? provider;
    for (final candidate in providers) {
      if (candidate.id == settings.selectedProviderId) provider = candidate;
    }
    final providerId = provider?.id ?? '';
    final modelsAsync = ref.watch(providerModelsProvider(providerId));
    final checkStatuses = ref.watch(modelCheckStatusesProvider(providerId)).when(
          data: (Map<String, bool> value) => value,
          loading: () => const <String, bool>{},
          error: (Object error, StackTrace stack) => const <String, bool>{},
        );
    final hasKey = ref.watch(hasApiKeyProvider(providerId)).when(
          data: (bool value) => value,
          loading: () => false,
          error: (Object error, StackTrace stack) => false,
        );
    final selectedModelId = settings.selectedModelId;

    if (provider == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.modelsTitle)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(l10n.errNoProvider, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (BuildContext routeContext) =>
                          const ProvidersScreen(),
                    ),
                  ),
                  icon: const Icon(Icons.add),
                  label: Text(l10n.addProvider),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.modelsTitle),
        actions: <Widget>[
          IconButton(
            tooltip: l10n.checkAllModels,
            onPressed: _checking ? null : () => _runCheck(provider!),
            icon: const Icon(Icons.fact_check_outlined),
          ),
          IconButton(
            onPressed: _checking
                ? null
                : () => ref.invalidate(providerModelsProvider(providerId)),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: <Widget>[
          ListTile(
            leading: const Icon(Icons.dns_outlined),
            title: Text(provider.name),
            subtitle: Text('${l10n.formatLabel}: ${provider.format.name}'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (BuildContext routeContext) =>
                    const ProvidersScreen(),
              ),
            ),
          ),
          if (!hasKey)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                l10n.modelsNoKey,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          if (_checking && _checkProgress != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  LinearProgressIndicator(
                    value: _checkProgress!.total == 0
                        ? null
                        : _checkProgress!.tested / _checkProgress!.total,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_checkProgress!.tested}/${_checkProgress!.total} · '
                    '${l10n.checkFailed(_checkProgress!.failed)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          if (_checkSummary != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                _checkSummary!,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.apply(color: Theme.of(context).colorScheme.primary),
              ),
            ),
          if (_checkError != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                _checkError!,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.apply(color: Theme.of(context).colorScheme.error),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              onChanged: (String value) =>
                  setState(() => _query = value.trim().toLowerCase()),
              decoration: InputDecoration(
                hintText: l10n.searchModels,
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(28),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          modelsAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (Object error, StackTrace stack) => Padding(
              padding: const EdgeInsets.all(24),
              child: Center(child: Text(l10n.errUnknown('$error'))),
            ),
            data: (List<ModelInfo> models) {
              final statuses = <String, bool>{}
                ..addAll(checkStatuses)
                ..addAll(_liveStatuses);
              final query = _query;
              final filtered = models.where((ModelInfo model) {
                if (query.isEmpty) return true;
                return model.id.toLowerCase().contains(query) ||
                    model.name.toLowerCase().contains(query);
              }).toList();
              if (filtered.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(child: Text(l10n.modelsEmpty)),
                );
              }
              return Column(
                children: <Widget>[
                  for (final model in filtered)
                    _ModelTile(
                      key: ValueKey<String>('$providerId/${model.id}'),
                      model: model,
                      providerId: providerId,
                      selected: model.id == selectedModelId,
                      checkStatus: statuses[model.id],
                    ),

                ],
              );
            },
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: _customController,
                    onSubmitted: (String value) =>
                        _applyCustomModel(providerId),
                    decoration: InputDecoration(
                      labelText: l10n.customModelLabel,
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(28),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () => _applyCustomModel(providerId),
                  child: Text(l10n.customModelApply),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _metaLine(ModelInfo model) {
  final parts = <String>[];
  final window = model.contextWindow;
  if (window != null) parts.add('${formatTokenCount(window)} ctx');
  final inputPrice = model.inputPricePerM;
  final outputPrice = model.outputPricePerM;
  if (inputPrice != null || outputPrice != null) {
    final inPart = inputPrice?.toStringAsFixed(2) ?? '-';
    final outPart = outputPrice?.toStringAsFixed(2) ?? '-';
    parts.add('\$$inPart/\$$outPart per 1M');
  }
  return parts.join(' · ');
}

IconData _modalityIcon(ModelModality modality) {
  switch (modality) {
    case ModelModality.image:
      return Icons.image;
    case ModelModality.video:
      return Icons.videocam;
    case ModelModality.audio:
      return Icons.mic_none;
  }
}

class _ModelTile extends ConsumerWidget {
  const _ModelTile({
    super.key,
    required this.model,
    required this.providerId,
    required this.selected,
    this.checkStatus,
  });

  final ModelInfo model;
  final String providerId;
  final bool selected;
  final bool? checkStatus;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final meta = _metaLine(model);
    final hasIcons = isReasoningModel(model.id) || model.modalities.isNotEmpty;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      decoration: checkStatus == false
          ? BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE53935)),
            )
          : null,
      child: ListTile(
      title: Text(model.name, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            model.id,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (meta.isNotEmpty || hasIcons)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (meta.isNotEmpty)
                    Flexible(
                      child: Text(
                        meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      ),
                    ),
                  if (isReasoningModel(model.id))
                    const Padding(
                      padding: EdgeInsets.only(left: 6),
                      child: Icon(Icons.psychology_outlined, size: 14),
                    ),
                  for (final modality in ModelModality.values)
                    if (model.modalities.contains(modality))
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: Icon(_modalityIcon(modality), size: 14),
                      ),
                ],
              ),
            ),
        ],
      ),
      trailing: _statusIcon(scheme),
      onTap: () async {
        await ref.read(settingsControllerProvider.notifier).selectModel(
              providerId: providerId,
              modelId: model.id,
              contextWindow: model.contextWindow,
              contextApproximate: model.approximateContext,
              inputPricePerM: model.inputPricePerM,
              outputPricePerM: model.outputPricePerM,
              modalities: model.modalities,
              reasoningEfforts: model.reasoningEfforts,
            );
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.modelSelected),
            duration: const Duration(seconds: 1),
          ),
        );
      },
      ),
    );
  }

  Widget? _statusIcon(ColorScheme scheme) {
    if (checkStatus == false) {
      return const Icon(Icons.cancel, color: Color(0xFFE53935));
    }
    if (selected) {
      return Icon(Icons.check_circle, color: scheme.primary);
    }
    if (checkStatus == true) {
      return const Icon(Icons.check_circle, color: Color(0xFF43A047));
    }
    return null;
  }
}
