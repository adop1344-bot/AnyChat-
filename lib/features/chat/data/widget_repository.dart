import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/storage/db.dart';

class ChatWidget {
  const ChatWidget({
    required this.id,
    required this.chatId,
    required this.type,
    required this.title,
    required this.config,
  });

  final int id;
  final int chatId;
  final String type;
  final String title;
  final Map<String, dynamic> config;

  static ChatWidget fromRow(ChatWidgetRow r) {
    Map<String, dynamic> cfg = <String, dynamic>{};
    try {
      final decoded = jsonDecode(r.config);
      if (decoded is Map<String, dynamic>) cfg = decoded;
    } catch (_) {}
    return ChatWidget(
      id: r.id,
      chatId: r.chatId,
      type: r.type,
      title: r.title,
      config: cfg,
    );
  }

  static const List<String> knownTypes = <String>['counter', 'note', 'todo'];
}

class WidgetRepository {
  WidgetRepository(this._db);

  final AppDatabase _db;

  Stream<List<ChatWidget>> watchByChat(int chatId) {
    final query = _db.select(_db.chatWidgets)
      ..where((t) => t.chatId.equals(chatId))
      ..orderBy([(t) => OrderingTerm.asc(t.id)]);
    return query.watch().map((rows) => rows.map(ChatWidget.fromRow).toList());
  }

  Future<int> insert({
    required int chatId,
    required String type,
    required String title,
    Map<String, dynamic> config = const <String, dynamic>{},
  }) {
    return _db.into(_db.chatWidgets).insert(
          ChatWidgetsCompanion.insert(
            chatId: chatId,
            type: type,
            title: Value(title),
            config: Value(jsonEncode(config)),
          ),
        );
  }

  Future<void> updateConfig(int id, Map<String, dynamic> config) {
    return (_db.update(_db.chatWidgets)..where((t) => t.id.equals(id)))
        .write(ChatWidgetsCompanion(config: Value(jsonEncode(config))));
  }

  Future<void> remove(int id) {
    return (_db.delete(_db.chatWidgets)..where((t) => t.id.equals(id))).go();
  }
}
