import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../app_providers.dart';
import '../../../core/errors/api_error.dart';
import '../data/provider_adapter.dart';
import '../../../core/storage/secure_storage.dart';
import '../data/provider_config_repository.dart';
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
    return adapterFor(provider.format).fetchModels(
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

const String _checkPrefix = 'model_check_';

Future<Map<String, bool>> _readModelStatuses(String providerId) async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString('$_checkPrefix$providerId');
  if (raw == null || raw.isEmpty) return <String, bool>{};
  try {
    final Object? decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) {
      return decoded.map((String k, Object? v) => MapEntry(k, v == true));
    }
  } catch (_) {}
  return <String, bool>{};
}

Future<void> _writeModelStatuses(
  String providerId,
  Map<String, bool> statuses,
) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('$_checkPrefix$providerId', jsonEncode(statuses));
  await prefs.remove('model_blacklist_$providerId');
}

@riverpod
Future<Map<String, bool>> modelCheckStatuses(Ref ref, String providerId) {
  return _readModelStatuses(providerId);
}

class ModelCheckProgress {
  const ModelCheckProgress({
    required this.tested,
    required this.total,
    required this.failed,
    required this.statuses,
  });

  final int tested;
  final int total;
  final int failed;
  final Map<String, bool> statuses;
}

class ModelCheckSummary {
  const ModelCheckSummary({required this.ok, required this.failed});

  final int ok;
  final int failed;
}

Future<ModelCheckSummary> checkAllProviderModels(
  ProviderConfigRepository repo,
  SecureKeyStore keyStore,
  CustomProvider provider, {
  void Function(ModelCheckProgress progress)? onProgress,
}) async {
  final key = (await keyStore.readKey(provider.id))?.trim() ?? '';
  final models = await adapterFor(provider.format).fetchModels(
    apiKey: key,
    baseUrl: provider.baseUrl,
  );
  final statuses = <String, bool>{};
  var next = 0;
  var tested = 0;
  Future<void> worker() async {
    while (next < models.length) {
      final model = models[next++];
      var ok = true;
      try {
        final adapter = adapterFor(provider.format);
        await for (final String delta in adapter
            .streamChat(ChatParams(
              apiKey: key,
              baseUrl: provider.baseUrl,
              model: model.id,
              turns: const <ChatTurn>[ChatTurn(role: 'user', content: 'hi')],
              maxTokens: 1,
              timeout: const Duration(seconds: 15),
            ))
            .timeout(const Duration(seconds: 45))) {
          if (delta.isNotEmpty) break;
        }
      } catch (_) {
        ok = false;
      }
      statuses[model.id] = ok;
      tested++;
      onProgress?.call(ModelCheckProgress(
        tested: tested,
        total: models.length,
        failed: statuses.values.where((bool v) => !v).length,
        statuses: Map<String, bool>.from(statuses),
      ));
    }
  }

  final workers = <Future<void>>[];
  final workerCount = models.length < 3 ? models.length : 3;
  for (var i = 0; i < workerCount; i++) {
    workers.add(worker());
  }
  await Future.wait(workers);
  await _writeModelStatuses(provider.id, statuses);
  final failed = statuses.values.where((bool v) => !v).length;
  return ModelCheckSummary(
    ok: models.length - failed,
    failed: failed,
  );
}
