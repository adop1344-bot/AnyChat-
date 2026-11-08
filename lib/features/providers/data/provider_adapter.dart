import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

import '../../../core/errors/api_error.dart';
import '../../../core/network/api_format.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/network/sse_parser.dart';
import '../../chat/domain/models.dart' as chat;
import '../domain/model_info.dart';
import 'anthropic_adapter.dart';
import 'gemini_adapter.dart';
import 'openai_adapter.dart';

/// One conversation turn as understood by every wire format.
class ChatTurn {
  const ChatTurn({
    required this.role,
    required this.content,
    this.attachments = const <chat.ChatAttachment>[],
  });

  /// `system`, `user` or `assistant`.
  final String role;
  final String content;

  /// Media attached to this turn (multimodal input).
  final List<chat.ChatAttachment> attachments;
}

/// A fully materialized HTTP request (URL + headers + JSON body).
class ChatRequest {
  const ChatRequest({
    required this.url,
    required this.headers,
    required this.body,
  });

  final String url;
  final Map<String, String> headers;
  final Map<String, dynamic> body;
}

/// Everything a request needs, independent of the wire format.
class ChatParams {
  const ChatParams({
    required this.apiKey,
    required this.baseUrl,
    required this.model,
    required this.turns,
    this.reasoningEffort,
    this.maxTokens,
    this.promptCaching = false,
    this.timeout = const Duration(seconds: 90),
  });

  final String apiKey;
  final String baseUrl;
  final String model;
  final List<ChatTurn> turns;

  /// `low` / `medium` / `high` for reasoning models (OpenAI-compatible);
  /// `null` = not sent.
  final String? reasoningEffort;
  final int? maxTokens;

  /// Anthropic-style explicit prompt cache breakpoints (server-side).
  final bool promptCaching;
  final Duration timeout;
}

/// Factory: wire format -> adapter.
ProviderAdapter adapterFor(ApiFormat format) {
  switch (format) {
    case ApiFormat.openai:
      return OpenAIAdapter();
    case ApiFormat.anthropic:
      return AnthropicAdapter();
    case ApiFormat.gemini:
      return GeminiAdapter();
  }
}

/// Strips trailing slashes so `/chat/completions` never doubles up.
String joinUrl(String baseUrl, String path) {
  final base = baseUrl.trimRight().replaceAll(RegExp(r'/+$'), '');
  final suffix = path.startsWith('/') ? path : '/$path';
  return '$base$suffix';
}

/// Lenient JSON decode shared by adapters: `null` when the payload is not
/// valid JSON (never throws).
Object? tryDecodeJson(String source) {
  final trimmed = source.trim();
  if (trimmed.isEmpty) return null;
  try {
    return jsonDecode(trimmed);
  } on FormatException {
    return null;
  }
}

/// Converts a per-token price (OpenRouter style) to USD per 1M tokens.
double? pricePerMillion(Object? value) {
  double? parsed;
  if (value is num) {
    parsed = value.toDouble();
  } else if (value is String) {
    parsed = double.tryParse(value);
  }
  if (parsed == null || parsed < 0) return null;
  if (parsed > 1) return parsed;
  return parsed * 1e6;
}

/// Usage numbers a provider happens to report mid-stream (never requested
/// explicitly, so no provider can reject the request because of this).
class ChatUsage {
  int? inputTokens;
  int? outputTokens;
  int? thinkingTokens;
}

/// Shared HTTP plumbing; subclasses only describe the wire format.
abstract class ProviderAdapter {
  ApiFormat get format;

  /// POST body/URL/headers for a streaming chat completion.
  ChatRequest buildChatRequest(ChatParams params);

  /// GET request listing the provider's models.
  ChatRequest buildModelsRequest({required String apiKey, required String baseUrl});

  /// Parses the `/models` payload (or returns an empty list on garbage).
  List<ModelInfo> parseModels(String jsonBody);

  /// Returns the text delta for one SSE event, `null` when the stream is
  /// finished, or throws [ApiError] when the provider reported an error.
/// One streamed chunk: visible answer text and/or model reasoning.
class StreamDelta {
  const StreamDelta({this.text = '', this.reasoning = ''});

  const StreamDelta.text(String value) : text = value, reasoning = '';

  const StreamDelta.reasoning(String value) : text = '', reasoning = value;

  final String text;
  final String reasoning;
}

  StreamDelta? parseStreamData(String data);

  /// Filled by [parseStreamData] when the provider reports usage
  /// (Gemini `usageMetadata`, Anthropic `usage`, OpenAI `usage`).
  ChatUsage? lastUsage;

  /// Sends a chat request and yields assistant text as it arrives.
  Stream<StreamDelta> streamChat(
    ChatParams params, {
    Dio? dio,
    CancelToken? cancelToken,
  }) async* {
    lastUsage = null;
    final request = buildChatRequest(params);
    final client = dio ?? DioClient.instance;
    final Response<ResponseBody> response;
    try {
      response = await client.post<ResponseBody>(
        request.url,
        options: Options(
          headers: request.headers,
          responseType: ResponseType.stream,
          validateStatus: (_) => true,
          connectTimeout: params.timeout,
        ),
        data: request.body,
        cancelToken: cancelToken,
      );
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) rethrow;
      throw ApiError.fromDio(e, format);
    }

    final status = response.statusCode ?? 0;
    final bodyStream = response.data?.stream;
    if (bodyStream == null) {
      throw ApiError(
        type: ApiErrorType.networkError,
        raw: 'empty response body (status $status)',
      );
    }

    if (status < 200 || status >= 300) {
      final raw = await utf8.decoder.bind(bodyStream).join();
      throw ApiError.fromResponse(
        statusCode: status,
        body: raw,
        format: format,
        headers: response.headers.map,
      );
    }

    try {
      final parser = SseParser();
      final events =
          utf8.decoder.bind(bodyStream).expand<SseEvent>(parser.addText);
      await for (final event in events) {
        final delta = parseStreamData(event.data);
        if (delta == null) return;
        if (delta.text.isNotEmpty || delta.reasoning.isNotEmpty) yield delta;
      }
      for (final event in parser.close()) {
        final delta = parseStreamData(event.data);
        if (delta == null) return;
        if (delta.text.isNotEmpty || delta.reasoning.isNotEmpty) yield delta;
      }
    } on ApiError {
      rethrow;
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) rethrow;
      throw ApiError.fromDio(e, format);
    } on SocketException catch (e) {
      throw ApiError(
        type: ApiErrorType.networkError,
        raw: '$e',
        cause: e,
      );
    } catch (e) {
      throw ApiError(type: ApiErrorType.unknown, raw: '$e', cause: e);
    }
  }

  /// Fetches the model catalog; callers fall back to a static list on error.
  Future<List<ModelInfo>> fetchModels({
    required String apiKey,
    required String baseUrl,
    Dio? dio,
  }) async {
    final request = buildModelsRequest(apiKey: apiKey, baseUrl: baseUrl);
    final client = dio ?? DioClient.instance;
    final Response<String> response;
    try {
      response = await client.get<String>(
        request.url,
        options: Options(
          headers: request.headers,
          responseType: ResponseType.plain,
          validateStatus: (_) => true,
          receiveTimeout: const Duration(seconds: 25),
        ),
      );
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) rethrow;
      throw ApiError.fromDio(e, format);
    }

    final status = response.statusCode ?? 0;
    final body = response.data ?? '';
    if (status < 200 || status >= 300) {
      throw ApiError.fromResponse(
        statusCode: status,
        body: body,
        format: format,
        headers: response.headers.map,
      );
    }
    return parseModels(body);
  }

  /// Collapses adjacent same-role turns (e.g. two user messages after a
  /// failed reply) so strict providers keep accepting the request.
  static List<ChatTurn> mergeTurns(List<ChatTurn> turns) {
    final merged = <ChatTurn>[];
    for (final turn in turns) {
      if (turn.content.trim().isEmpty && turn.attachments.isEmpty) continue;
      if (merged.isNotEmpty && merged.last.role == turn.role) {
        final previous = merged.removeLast();
        merged.add(ChatTurn(
          role: turn.role,
          content: _joinText(previous.content, turn.content),
          attachments: <chat.ChatAttachment>[
            ...previous.attachments,
            ...turn.attachments,
          ],
        ));
      } else {
        merged.add(turn);
      }
    }
    return merged;
  }

  static String _joinText(String first, String second) {
    if (first.trim().isEmpty) return second;
    if (second.trim().isEmpty) return first;
    return '$first\n\n$second';
  }

  /// Joins system turns into a single system prompt, or `null`.
  static String? systemPromptOf(List<ChatTurn> turns) {
    final parts = turns
        .where((t) => t.role == 'system' && t.content.trim().isNotEmpty)
        .map((t) => t.content.trim())
        .toList();
    if (parts.isEmpty) return null;
    return parts.join('\n\n');
  }
}
