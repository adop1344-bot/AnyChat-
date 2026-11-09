import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/storage/db.dart';
import 'core/storage/secure_storage.dart';
import 'features/chat/data/chat_repository.dart';
import 'features/chat/data/widget_repository.dart';
import 'features/chat/data/message_repository.dart';
import 'features/providers/data/provider_config_repository.dart';

final databaseProvider = Provider<AppDatabase>((ref) {
  final database = AppDatabase();
  ref.onDispose(() => database.close());
  return database;
});

final chatRepositoryProvider = Provider<ChatRepository>(
  (ref) => ChatRepository(ref.watch(databaseProvider)),
);

final messageRepositoryProvider = Provider<MessageRepository>(
  (ref) => MessageRepository(ref.watch(databaseProvider)),
);

final widgetRepositoryProvider = Provider<WidgetRepository>(
  (ref) => WidgetRepository(ref.watch(databaseProvider)),
);

final widgetListProvider = StreamProvider.autoDispose
    .family<List<ChatWidget>, int>(
  (ref, chatId) => ref.watch(widgetRepositoryProvider).watchByChat(chatId),
);

final providerConfigRepositoryProvider = Provider<ProviderConfigRepository>(
  (ref) => ProviderConfigRepository(ref.watch(databaseProvider)),
);

final keyStoreProvider = Provider<SecureKeyStore>((ref) => SecureKeyStore());
