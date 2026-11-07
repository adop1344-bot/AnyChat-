import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/storage/token_estimator.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../providers/domain/custom_provider.dart';
import '../../../providers/domain/model_info.dart';
import '../../../providers/state/providers_state.dart';
import '../../../settings/app_settings.dart';
import '../../../settings/state/settings_controller.dart';

class ModelPickerSheet extends ConsumerStatefulWidget {
  const ModelPickerSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (BuildContext sheetContext) => const ModelPickerSheet(),
    );
  }

  @override
  ConsumerState<ModelPickerSheet> createState() => _ModelPickerSheetState();
}

class _ModelPickerSheetState extends ConsumerState<ModelPickerSheet> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  String? _providerFilter;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final providers = ref.watch(customProvidersProvider).when(
          data: (List<CustomProvider> value) => value,
          loading: () => const <CustomProvider>[],
          error: (Object error, StackTrace stack) =>
              const <CustomProvider>[],
        );
    final visible = _providerFilter == null
        ? providers
        : providers
            .where((CustomProvider p) => p.id == _providerFilter)
            .toList();

    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.82,
      child: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              controller: _searchController,
              onChanged: (String value) =>
                  setState(() => _query = value.trim().toLowerCase()),
              decoration: InputDecoration(
                hintText: l10n.searchModelHint,
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
          Expanded(
            child: providers.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        l10n.errNoProvider,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.only(bottom: 8),
                    children: <Widget>[
                      for (final provider in visible)
                        _ProviderGroup(
                          provider: provider,
                          query: _query,
                        ),
                    ],
                  ),
          ),
          _ProviderFilterBar(
            providers: providers,
            activeId: _providerFilter,
            onSelected: (String? id) => setState(() => _providerFilter = id),
          ),
        ],
      ),
    );
  }
}

class _ProviderGroup extends ConsumerWidget {
  const _ProviderGroup({required this.provider, required this.query});

  final CustomProvider provider;
  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final modelsAsync = ref.watch(providerModelsProvider(provider.id));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
          child: Text(
            provider.name,
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        modelsAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
          error: (Object error, StackTrace stack) => Padding(
            padding: const EdgeInsets.all(16),
            child: Text(l10n.errUnknown('$error')),
          ),
          data: (List<ModelInfo> models) {
            final filtered = models.where((ModelInfo model) {
              if (query.isEmpty) return true;
              return model.id.toLowerCase().contains(query) ||
                  model.name.toLowerCase().contains(query);
            }).toList();
            if (filtered.isEmpty) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: Text(
                  models.isEmpty
                      ? l10n.noModelsProvider
                      : l10n.modelsEmpty,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              );
            }
            return Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Column(
                children: <Widget>[
                  for (final model in filtered)
                    _ModelCard(
                      providerId: provider.id,
                      model: model,
                    ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

class _ModelCard extends ConsumerWidget {
  const _ModelCard({required this.providerId, required this.model});

  final String providerId;
  final ModelInfo model;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final settings = ref.watch(settingsControllerProvider).when(
          data: (AppSettings value) => value,
          loading: () => const AppSettings(),
          error: (Object error, StackTrace stack) => const AppSettings(),
        );
    final selected = settings.selectedProviderId == providerId &&
        settings.selectedModelId == model.id;
    final favoriteKey = '$providerId/${model.id}';
    final isFavorite = settings.favoriteModels.contains(favoriteKey);
    final reasoning = model.reasoningEfforts.isNotEmpty ||
        isReasoningModel(model.id);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected
            ? theme.colorScheme.primary
            : theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            ref.read(settingsControllerProvider.notifier).selectModel(
                  providerId: providerId,
                  modelId: model.id,
                );
            Navigator.of(context).pop();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: <Widget>[
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: selected
                        ? theme.colorScheme.onPrimary.withValues(alpha: 0.15)
                        : theme.colorScheme.surfaceContainerHighest,
                  ),
                  child: Text(
                    model.name.isNotEmpty
                        ? model.name.substring(0, 1).toUpperCase()
                        : '?',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: selected
                          ? theme.colorScheme.onPrimary
                          : theme.colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        model.id,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: selected
                              ? theme.colorScheme.onPrimary
                              : theme.colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: <Widget>[
                          _Badge(
                            label: l10n.badgeChat,
                            color: const Color(0xFF2962FF),
                            selected: selected,
                          ),
                          if (reasoning)
                            _Badge(
                              icon: Icons.psychology,
                              color: const Color(0xFFD84315),
                              selected: selected,
                            ),
                          for (final modality in model.modalities)
                            _Badge(
                              icon: switch (modality) {
                                ModelModality.image => Icons.image,
                                ModelModality.video => Icons.videocam,
                                ModelModality.audio => Icons.mic,
                              },
                              color: const Color(0xFF2962FF),
                              selected: selected,
                            ),
                          if (model.contextWindow != null)
                            _Badge(
                              label: formatTokenCount(model.contextWindow!),
                              color: theme.colorScheme.outline,
                              selected: selected,
                              neutral: true,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: l10n.favoriteModel,
                  icon: isFavorite
                      ? Icon(
                          Icons.favorite,
                          size: 20,
                          color: selected
                              ? theme.colorScheme.onPrimary
                              : theme.colorScheme.primary,
                        )
                      : Icon(
                          Icons.favorite_border,
                          size: 20,
                          color: selected
                              ? theme.colorScheme.onPrimary
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                  onPressed: () => ref
                      .read(settingsControllerProvider.notifier)
                      .toggleFavoriteModel(favoriteKey),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({
    required this.color,
    required this.selected,
    this.label,
    this.icon,
    this.neutral = false,
  });

  final String? label;
  final IconData? icon;
  final Color color;
  final bool selected;
  final bool neutral;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final badgeColor =
        selected ? theme.colorScheme.onPrimary.withValues(alpha: 0.2) : color;
    final foreground = selected
        ? theme.colorScheme.onPrimary
        : (neutral ? theme.colorScheme.onSurfaceVariant : Colors.white);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: neutral ? Colors.transparent : badgeColor,
        borderRadius: BorderRadius.circular(8),
        border: neutral
            ? Border.all(
                color: selected
                    ? theme.colorScheme.onPrimary.withValues(alpha: 0.5)
                    : color,
              )
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null)
            Icon(icon, size: 12, color: foreground)
          else if (label != null)
            Text(
              label!,
              style: theme.textTheme.labelSmall?.copyWith(color: foreground),
            ),
        ],
      ),
    );
  }
}

class _ProviderFilterBar extends StatelessWidget {
  const _ProviderFilterBar({
    required this.providers,
    required this.activeId,
    required this.onSelected,
  });

  final List<CustomProvider> providers;
  final String? activeId;
  final void Function(String? id) onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        border: Border(
          top: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
      ),
      child: SizedBox(
        height: 60,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          children: <Widget>[
            _ProviderPill(
              label: l10n.allProviders,
              avatarText: null,
              active: activeId == null,
              onTap: () => onSelected(null),
            ),
            for (final provider in providers)
              _ProviderPill(
                label: provider.name,
                avatarText: provider.name.isNotEmpty
                    ? provider.name.substring(0, 1).toUpperCase()
                    : '?',
                active: activeId == provider.id,
                onTap: () => onSelected(provider.id),
              ),
          ],
        ),
      ),
    );
  }
}

class _ProviderPill extends StatelessWidget {
  const _ProviderPill({
    required this.label,
    required this.active,
    required this.onTap,
    this.avatarText,
  });

  final String label;
  final String? avatarText;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: active ? theme.colorScheme.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(22),
            border: active
                ? null
                : Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Row(
            children: <Widget>[
              if (avatarText != null) ...<Widget>[
                CircleAvatar(
                  radius: 12,
                  backgroundColor: active
                      ? theme.colorScheme.onPrimary.withValues(alpha: 0.2)
                      : theme.colorScheme.surfaceContainerHighest,
                  child: Text(
                    avatarText!,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: active
                          ? theme.colorScheme.onPrimary
                          : theme.colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Text(
                label,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: active
                      ? theme.colorScheme.onPrimary
                      : theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class CurrentModelChip extends ConsumerWidget {
  const CurrentModelChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final settings = ref.watch(settingsControllerProvider).when(
          data: (AppSettings value) => value,
          loading: () => const AppSettings(),
          error: (Object error, StackTrace stack) => const AppSettings(),
        );
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => ModelPickerSheet.show(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.8,
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.smart_toy_outlined,
              size: 14,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                settings.selectedModelId ?? l10n.pickModelTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
