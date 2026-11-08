import 'package:drift/drift.dart';

import '../../../core/storage/db.dart';
import '../domain/models.dart' as dm;

class MessageRepository {
  MessageRepository(this._db);

  final AppDatabase _db;

  Stream<List<dm.Message>> watchMessages(int chatId) {
    final query = _db.select(_db.messages)
      ..where((t) => t.chatId.equals(chatId))
      ..orderBy([(t) => OrderingTerm.asc(t.id)]);
    return query.watch().map((rows) => rows.map(dm.Message.fromRow).toList());
  }

  Future<List<dm.Message>> messagesInBranch(int branchId) {
    final query = _db.select(_db.messages)
      ..where((t) => t.branchId.equals(branchId))
      ..orderBy([(t) => OrderingTerm.asc(t.id)]);
    return query.get().then((rows) => rows.map(dm.Message.fromRow).toList());
  }

  Future<int> insertMessage({
    required int chatId,
    required int branchId,
    required String role,
    String content = '',
    String? model,
    int? parentId,
    String? attachments,
  }) {
    return _db.into(_db.messages).insert(
          MessagesCompanion.insert(
            chatId: chatId,
            branchId: branchId,
            parentId: Value(parentId),
            role: role,
            content: Value(content),
            model: Value(model),
            attachments: Value(attachments),
          ),
        );
  }

  Future<void> setContent(int messageId, String content) {
    return (_db.update(_db.messages)..where((t) => t.id.equals(messageId)))
        .write(MessagesCompanion(content: Value(content)));
  }

  Future<void> setReasoning(int messageId, String reasoning) {
    return (_db.update(_db.messages)..where((t) => t.id.equals(messageId)))
        .write(
          MessagesCompanion(reasoning: Value(reasoning.isEmpty ? null : reasoning)),
        );
  }

  Future<void> setError(
    int messageId, {
    required String? errorType,
    required String? errorDetails,
  }) {
    return (_db.update(_db.messages)..where((t) => t.id.equals(messageId)))
        .write(
      MessagesCompanion(
        errorType: Value(errorType),
        errorDetails: Value(errorDetails),
      ),
    );
  }

  Future<void> deleteMessage(int messageId) {
    return (_db.delete(_db.messages)..where((t) => t.id.equals(messageId)))
        .go();
  }
}
