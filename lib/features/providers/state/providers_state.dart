import 'package:dio/dio.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../app_providers.dart';
import '../../../core/errors/api_error.dart';
import '../data/provider_adapter.dart';
import '../domain/custom_provider.dart';
import '../domain/model_info.dart';

part 'providers_state.g.dart';

@riverpod
Stream<List<CustomProvider>> customProviders(Ref ref) =>
    ref.watch(providerConfigRepositoryProvider).watchAll();

@riverpod
Future<bool> hasApiKey(Ref ref, String providerId) async {
  final keyStore = ref.watch(keyStoreProvider);
  final key = await keyStore.readKey(providerId);
  return key != null && key.trim().isNotEmpty;
}

@riverpod
Future<List<ModelInfo>> providerModels(Ref ref, String providerId) async {
  final repo = ref.watch(providerConfigRepositoryProvider);
  final keyStore = ref.watch(keyStoreProvider);
  final provider = await repo.getProvider(providerId);
  if (provider == null) return const <ModelInfo>[];
  final key = await keyStore.readKey(providerId);
  if (key == null || key.trim().isEmpty) return const <ModelInfo>[];
  try {
    return await adapterFor(provider.format).fetchModels(
      apiKey: key.trim(),
      baseUrl: provider.baseUrl,
    );
  } catch (_) {
    return const <ModelInfo>[];
  }
}

enum ProviderHealthState { ok, reachable, down, unknown }

class ProviderHealth {
  const ProviderHealth({required this.state, required this.ms});

  final ProviderHealthState state;
  final int ms;
}

@riverpod
Future<ProviderHealth> providerHealth(Ref ref, String providerId) async {
  final repo = ref.watch(providerConfigRepositoryProvider);
  final keyStore = ref.watch(keyStoreProvider);
  final provider = await repo.getProvider(providerId);
  if (provider == null) {
    return const ProviderHealth(state: ProviderHealthState.unknown, ms: 0);
  }
  final key = (await keyStore.readKey(providerId))?.trim() ?? '';
  final dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 6),
    receiveTimeout: const Duration(seconds: 8),
  ));
  final stopwatch = Stopwatch()..start();
  try {
    await adapterFor(provider.format).fetchModels(
      apiKey: key,
      baseUrl: provider.baseUrl,
      dio: dio,
    );
    stopwatch.stop();
    return ProviderHealth(
      state: ProviderHealthState.ok,
      ms: stopwatch.elapsedMilliseconds,
    );
  } on ApiError catch (error) {
    stopwatch.stop();
    final down = error.type == ApiErrorType.networkError;
    return ProviderHealth(
      state: down ? ProviderHealthState.down : ProviderHealthState.reachable,
      ms: stopwatch.elapsedMilliseconds,
    );
  } catch (_) {
    stopwatch.stop();
    return ProviderHealth(
      state: ProviderHealthState.down,
      ms: stopwatch.elapsedMilliseconds,
    );
  }
}
