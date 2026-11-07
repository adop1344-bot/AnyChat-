import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

  @override
  void dispose() {
    _customController.dispose();
    super.dispose();
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
    final hiddenCount = ref.watch(hiddenModelCountProvider(providerId)).when(
          data: (int value) => value,
          loading: () => 0,
          error: (Object error, StackTrace stack) => 0,
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
            onPressed: () =>
                ref.invalidate(providerModelsProvider(providerId)),
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
          if (hiddenCount > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                children: <Widget>[
                  Icon(
                    Icons.visibility_off_outlined,
                    size: 16,
                    color: Theme.of(context).colorScheme.tertiary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      l10n.hiddenModelsCount(hiddenCount),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
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
  });

  final ModelInfo model;
  final String providerId;
  final bool selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final meta = _metaLine(model);
    final hasIcons = isReasoningModel(model.id) || model.modalities.isNotEmpty;

    return ListTile(
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
      trailing: selected ? Icon(Icons.check_circle, color: scheme.primary) : null,
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
    );
  }
}
