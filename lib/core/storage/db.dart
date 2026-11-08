import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'db.g.dart';

class Chats extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get title => text().withDefault(const Constant('New chat'))();
  TextColumn get systemPrompt => text().nullable()();
  IntColumn get activeBranchId => integer().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  /// Cumulative usage reported by the provider (or estimated locally).
  IntColumn get usageInput => integer().withDefault(const Constant(0))();
  IntColumn get usageOutput => integer().withDefault(const Constant(0))();
  IntColumn get usageThinking => integer().withDefault(const Constant(0))();
}

@DataClassName('Branch')
class Branches extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get chatId => integer()();
  TextColumn get name => text().withDefault(const Constant('main'))();
  IntColumn get forkedFromMessageId => integer().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

class Messages extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get chatId => integer()();
  IntColumn get branchId => integer()();
  IntColumn get parentId => integer().nullable()();
  TextColumn get role => text()();
  TextColumn get content => text().withDefault(const Constant(''))();
  TextColumn get reasoning => text().nullable()();

  /// JSON array of {@link ChatAttachment} objects (base64 payloads) —
  /// added in schema v2 for multimodal input.
  TextColumn get attachments => text().nullable()();
  TextColumn get model => text().nullable()();
  TextColumn get errorType => text().nullable()();
  TextColumn get errorDetails => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// User-defined providers (never holds API keys).
///
/// `baseUrlOverride` is a legacy column from the preset-provider era; the
/// migration (schema v3 -> v4) copies it into [baseUrl] and fills
/// [name]/[format] from the old registry.
@DataClassName('ProviderConfig')
class ProvidersConfig extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get providerId => text().unique()();
  TextColumn get baseUrlOverride => text().nullable()();
  TextColumn get name => text().withDefault(const Constant(''))();
  TextColumn get baseUrl => text().withDefault(const Constant(''))();
  TextColumn get format => text().withDefault(const Constant('openai'))();
}

@DriftDatabase(tables: [Chats, Messages, Branches, ProvidersConfig])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(driftDatabase(name: 'anychat'));

  /// In-memory database for unit tests.
  AppDatabase.memory() : super(NativeDatabase.memory());

  @override
  int get schemaVersion => 5;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.addColumn(messages, messages.attachments);
          }
          if (from < 3) {
            await m.addColumn(chats, chats.usageInput);
            await m.addColumn(chats, chats.usageOutput);
            await m.addColumn(chats, chats.usageThinking);
          }
          if (from < 5) {
            await m.addColumn(messages, messages.reasoning);
          }
          if (from < 4) {
            await m.addColumn(providersConfig, providersConfig.name);
            await m.addColumn(providersConfig, providersConfig.baseUrl);
            await m.addColumn(providersConfig, providersConfig.format);
            await _backfillCustomProviders();
          }
        },
      );

  /// Fills the new custom-provider columns for rows created while presets
  /// still existed (keeps the stored API keys working under the same id).
  Future<void> _backfillCustomProviders() async {
    final rows = await select(providersConfig).get();
    for (final row in rows) {
      final legacy = _legacyProviders[row.providerId];
      if (legacy == null) continue;
      await (update(providersConfig)..where((t) => t.id.equals(row.id)))
          .write(ProvidersConfigCompanion(
        name: Value(legacy.name),
        baseUrl: Value(row.baseUrlOverride ?? legacy.baseUrl),
        format: Value(legacy.format),
      ));
    }
  }
}

/// Old built-in registry, used only to migrate existing installations.
const Map<String, ({String name, String baseUrl, String format})>
    _legacyProviders =
    <String, ({String name, String baseUrl, String format})>{
  'openai': (name: 'OpenAI', baseUrl: 'https://api.openai.com/v1', format: 'openai'),
  'openrouter': (name: 'OpenRouter', baseUrl: 'https://openrouter.ai/api/v1', format: 'openai'),
  'deepseek': (name: 'DeepSeek', baseUrl: 'https://api.deepseek.com/v1', format: 'openai'),
  'xiaomi': (name: 'Xiaomi MiMo', baseUrl: 'https://api.xiaomimimo.com/v1', format: 'openai'),
  'together': (name: 'Together AI', baseUrl: 'https://api.together.xyz/v1', format: 'openai'),
  'groq': (name: 'Groq', baseUrl: 'https://api.groq.com/openai/v1', format: 'openai'),
  'fireworks': (name: 'Fireworks', baseUrl: 'https://api.fireworks.ai/inference/v1', format: 'openai'),
  'novita': (name: 'Novita AI', baseUrl: 'https://api.novita.ai/v3/openai', format: 'openai'),
  'deepinfra': (name: 'DeepInfra', baseUrl: 'https://api.deepinfra.com/v1/openai', format: 'openai'),
  'mistral': (name: 'Mistral', baseUrl: 'https://api.mistral.ai/v1', format: 'openai'),
  'xai': (name: 'xAI', baseUrl: 'https://api.x.ai/v1', format: 'openai'),
  'perplexity': (name: 'Perplexity', baseUrl: 'https://api.perplexity.ai', format: 'openai'),
  'hyperbolic': (name: 'Hyperbolic', baseUrl: 'https://api.hyperbolic.xyz/v1', format: 'openai'),
  'cerebras': (name: 'Cerebras', baseUrl: 'https://api.cerebras.ai/v1', format: 'openai'),
  'sambanova': (name: 'SambaNova', baseUrl: 'https://api.sambanova.ai/v1', format: 'openai'),
  'lambda': (name: 'Lambda', baseUrl: 'https://api.lambdalabs.com/v1', format: 'openai'),
  'cohere': (name: 'Cohere', baseUrl: 'https://api.cohere.com/compatibility/v1', format: 'openai'),
  'ollama': (name: 'Ollama (local)', baseUrl: 'http://10.0.2.2:11434/v1', format: 'openai'),
  'vercel': (name: 'Vercel AI Gateway', baseUrl: 'https://ai-gateway.vercel.sh/v1', format: 'openai'),
  'anthropic': (name: 'Anthropic', baseUrl: 'https://api.anthropic.com/v1', format: 'anthropic'),
  'gemini': (name: 'Google Gemini', baseUrl: 'https://generativelanguage.googleapis.com/v1beta', format: 'gemini'),
};
