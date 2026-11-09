import '../../../core/storage/db.dart' as db;

import 'dart:convert';

/// Domain models for the chat feature.
///
/// Deliberately hand-written instead of reusing the drift row classes:
/// `riverpod_generator` cannot resolve types generated into `db.g.dart`
/// (a `part` file), which failed with `InvalidTypeException` during
/// code generation. Repositories map rows via the `fromRow` factories.
class Chat {
  const Chat({
    required this.id,
    required this.title,
    this.systemPrompt,
    this.activeBranchId,
    required this.createdAt,
    this.usageInput = 0,
    this.usageOutput = 0,
    this.usageThinking = 0,
  });

  final int id;
  final String title;
  final String? systemPrompt;
  final int? activeBranchId;
  final DateTime createdAt;

  /// Cumulative usage over the whole chat (reported or estimated).
  final int usageInput;
  final int usageOutput;
  final int usageThinking;

  factory Chat.fromRow(db.Chat row) => Chat(
        id: row.id,
        title: row.title,
        systemPrompt: row.systemPrompt,
        activeBranchId: row.activeBranchId,
        createdAt: row.createdAt,
        usageInput: row.usageInput,
        usageOutput: row.usageOutput,
        usageThinking: row.usageThinking,
      );
}

/// One file attachment carried by a message (photos, video, audio).
class ChatAttachment {
  const ChatAttachment({
    required this.mimeType,
    required this.name,
    required this.data,
  });

  /// e.g. `image/png`, `video/mp4`, `audio/mpeg`.
  final String mimeType;

  /// Original file name, shown in chips and bubbles.
  final String name;

  /// Base64 payload.
  final String data;

  factory ChatAttachment.fromBytes({
    required String mimeType,
    required String name,
    required List<int> bytes,
  }) =>
      ChatAttachment(
        mimeType: mimeType,
        name: name,
        data: base64Encode(bytes),
      );

  factory ChatAttachment.fromJson(Map<String, dynamic> json) =>
      ChatAttachment(
        mimeType: json['mime'] is String
            ? json['mime'] as String
            : 'application/octet-stream',
        name: json['name'] is String ? json['name'] as String : 'file',
        data: json['data'] is String ? json['data'] as String : '',
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'mime': mimeType,
        'name': name,
        'data': data,
      };

  String get kind => mimeType.split('/').first;

  bool get isImage => kind == 'image';
  bool get isVideo => kind == 'video';
  bool get isAudio => kind == 'audio';
}

class ToolStep {
  const ToolStep({
    required this.kind,
    required this.argument,
    this.summary = '',
  });

  /// `SEARCH` / `OPEN` / `WIDGET`.
  final String kind;
  final String argument;
  final String summary;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'kind': kind,
        'argument': argument,
        'summary': summary,
      };

  factory ToolStep.fromJson(Map<String, dynamic> json) => ToolStep(
        kind: (json['kind'] ?? '').toString(),
        argument: (json['argument'] ?? '').toString(),
        summary: (json['summary'] ?? '').toString(),
      );

  static String encodeList(List<ToolStep> steps) =>
      jsonEncode(<Map<String, dynamic>>[for (final s in steps) s.toJson()]);

  static List<ToolStep> decodeList(String? raw) {
    if (raw == null || raw.isEmpty) return const <ToolStep>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return <ToolStep>[
          for (final item in decoded)
            if (item is Map<String, dynamic>) ToolStep.fromJson(item),
        ];
      }
    } on FormatException {
      return const <ToolStep>[];
    }
    return const <ToolStep>[];
  }
}

class Message {
  const Message({
    required this.id,
    required this.chatId,
    required this.branchId,
    this.parentId,
    required this.role,
    this.content = '',
    this.reasoning,
    this.model,
    this.errorType,
    this.errorDetails,
    this.attachments = const <ChatAttachment>[],
    this.toolSteps = const <ToolStep>[],
    required this.createdAt,
  });

  final int id;
  final int chatId;
  final int branchId;
  final int? parentId;

  /// `system`, `user` or `assistant`.
  final String role;
  final String content;

  /// Model reasoning (`<think>` or reasoning deltas), kept out of content.
  final String? reasoning;
  final String? model;

  /// [ApiErrorType.name] of the last failure, if the reply failed.
  final String? errorType;
  final String? errorDetails;

  /// Media attached to a user message (empty for text-only messages).
  final List<ChatAttachment> attachments;

  /// Tool calls made while producing this reply (search, widgets).
  final List<ToolStep> toolSteps;

  final DateTime createdAt;

  factory Message.fromRow(db.Message row) => Message(
        id: row.id,
        chatId: row.chatId,
        branchId: row.branchId,
        parentId: row.parentId,
        role: row.role,
        content: row.content,
        reasoning: row.reasoning,
        model: row.model,
        errorType: row.errorType,
        errorDetails: row.errorDetails,
        attachments: parseAttachments(row.attachments),
        toolSteps: ToolStep.decodeList(row.toolSteps),
        createdAt: row.createdAt,
      );

  /// Lenient JSON parse: malformed payloads yield no attachments.
  static List<ChatAttachment> parseAttachments(String? raw) {
    if (raw == null || raw.isEmpty) return const <ChatAttachment>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return <ChatAttachment>[
          for (final item in decoded)
            if (item is Map<String, dynamic>) ChatAttachment.fromJson(item),
        ];
      }
    } on FormatException {
      return const <ChatAttachment>[];
    }
    return const <ChatAttachment>[];
  }

  /// Serializes [attachments] for the storage layer.
  static String? encodeAttachments(List<ChatAttachment> attachments) {
    if (attachments.isEmpty) return null;
    return jsonEncode(
      <Map<String, dynamic>>[for (final a in attachments) a.toJson()],
    );
  }
}

class Branch {
  const Branch({
    required this.id,
    required this.chatId,
    this.name = 'main',
    this.forkedFromMessageId,
    required this.createdAt,
  });

  final int id;
  final int chatId;
  final String name;
  final int? forkedFromMessageId;
  final DateTime createdAt;

  factory Branch.fromRow(db.Branch row) => Branch(
        id: row.id,
        chatId: row.chatId,
        name: row.name,
        forkedFromMessageId: row.forkedFromMessageId,
        createdAt: row.createdAt,
      );
}

/// Derives a chat title from the first user message: whitespace-normalized
/// and cut at a word boundary around 40 characters.
String deriveChatTitle(String text) {
  final normalized = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (normalized.isEmpty) return 'New chat';
  if (normalized.length <= 40) return normalized;
  final cut = normalized.substring(0, 40);
  final lastSpace = cut.lastIndexOf(' ');
  if (lastSpace > 10) return cut.substring(0, lastSpace).trimRight();
  return cut.trimRight();
}
