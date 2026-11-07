import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../providers/domain/model_info.dart';
import '../app_settings.dart';

part 'settings_controller.g.dart';

@riverpod
class SettingsController extends _$SettingsController {
  @override
  Future<AppSettings> build() async {
    final prefs = await SharedPreferences.getInstance();
    return AppSettings.fromPrefs(prefs);
  }

  AppSettings? get _value {
    final current = state;
    if (current is AsyncData<AppSettings>) return current.value;
    return null;
  }

  Future<void> _update(AppSettings Function(AppSettings change) change) async {
    final current = _value;
    if (current == null) return;
    final next = change(current);
    state = AsyncData(next);
    final prefs = await SharedPreferences.getInstance();
    await next.persist(prefs);
  }

  Future<void> setThemeMode(String value) =>
      _update((s) => s.copyWith(themeMode: value));

  Future<void> setLocale(String? value) =>
      _update((s) => s.copyWith(localeCode: value));

  Future<void> setMaxTokens(int? value) =>
      _update((s) => s.copyWith(maxTokens: value));

  Future<void> setTimeoutSeconds(int value) =>
      _update((s) => s.copyWith(timeoutSeconds: value));

  Future<void> setSystemPrompt(String value) =>
      _update((s) => s.copyWith(systemPrompt: value));

  Future<void> setContextLimit(int? value) =>
      _update((s) => s.copyWith(contextLimit: value));

  Future<void> setHistoryDepth(int? value) =>
      _update((s) => s.copyWith(historyDepth: value));

  Future<void> setAccentColor(String value) =>
      _update((s) => s.copyWith(accentColor: value));

  Future<void> setReasoningEffort(String value) =>
      _update((s) => s.copyWith(reasoningEffort: value));

  Future<void> setPromptCaching(bool value) =>
      _update((s) => s.copyWith(promptCaching: value));

  Future<void> toggleFavoriteModel(String key) => _update(
        (s) => s.copyWith(
          favoriteModels: s.favoriteModels.contains(key)
              ? (<String>[...s.favoriteModels]..remove(key))
              : <String>[...s.favoriteModels, key],
        ),
      );

  Future<void> selectProvider(String providerId) => _update(
        (s) => s
            .copyWith(selectedProviderId: providerId)
            .withoutModel(),
      );

  Future<void> selectModel({
    required String providerId,
    required String modelId,
    int? contextWindow,
    bool contextApproximate = true,
    double? inputPricePerM,
    double? outputPricePerM,
    Set<ModelModality> modalities = const <ModelModality>{},
    List<String> reasoningEfforts = const <String>[],
  }) {
    return _update(
      (s) => s.copyWith(
        selectedProviderId: providerId,
        selectedModelId: modelId,
        modelContextWindow: contextWindow,
        modelContextApproximate: contextApproximate,
        modelInputPricePerM: inputPricePerM,
        modelOutputPricePerM: outputPricePerM,
        modelModalities: modalities,
        modelReasoningEfforts: reasoningEfforts,
      ),
    );
  }
}
