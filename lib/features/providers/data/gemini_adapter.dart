import '../../../core/errors/api_error.dart';
import '../../../core/network/api_format.dart';
import '../domain/model_info.dart';
import 'provider_adapter.dart';

class GeminiAdapter extends ProviderAdapter {
  @override
  ApiFormat get format => ApiFormat.gemini;

  @override
  ChatRequest buildChatRequest(ChatParams params) {
    final turns = ProviderAdapter.mergeTurns(params.turns);
    final system = ProviderAdapter.systemPromptOf(turns);
    final contents = <Map<String, dynamic>>[];
    for (final turn in turns) {
      if (turn.role == 'system') continue;
      contents.add(<String, dynamic>{
        'role': turn.role == 'assistant' ? 'model' : 'user',
        'parts': _partsFor(turn),
      });
    }
    final resource = params.model.startsWith('models/')
        ? params.model
        : 'models/${params.model}';
    final url =
        '${joinUrl(params.baseUrl, '/$resource')}:streamGenerateContent'
        '?alt=sse&key=${Uri.encodeQueryComponent(params.apiKey)}';
    return ChatRequest(
      url: url,
      headers: const <String, String>{},
      body: <String, dynamic>{
        if (system != null)
          'systemInstruction': <String, dynamic>{
            'parts': <Map<String, String>>[
              <String, String>{'text': system},
            ],
          },
        'contents': contents,
        if (params.maxTokens != null)
          'generationConfig': <String, dynamic>{
            'maxOutputTokens': params.maxTokens,
          },
      },
    );
  }

  static List<Map<String, dynamic>> _partsFor(ChatTurn turn) {
    final parts = <Map<String, dynamic>>[];
    if (turn.content.isNotEmpty) {
      parts.add(<String, dynamic>{'text': turn.content});
    }
    for (final attachment in turn.attachments) {
      parts.add(<String, dynamic>{
        'inlineData': <String, dynamic>{
          'mimeType': attachment.mimeType,
          'data': attachment.data,
        },
      });
    }
    if (parts.isEmpty) {
      parts.add(<String, dynamic>{'text': turn.content});
    }
    return parts;
  }

  @override
  ChatRequest buildModelsRequest({
    required String apiKey,
    required String baseUrl,
  }) {
    return ChatRequest(
      url: '${joinUrl(baseUrl, '/models')}'
          '?key=${Uri.encodeQueryComponent(apiKey)}',
      headers: const <String, String>{},
      body: const <String, dynamic>{},
    );
  }

  @override
  List<ModelInfo> parseModels(String jsonBody) {
    final decoded = tryDecodeJson(jsonBody);
    if (decoded is! Map) return const <ModelInfo>[];
    final models = decoded['models'];
    if (models is! List) return const <ModelInfo>[];
    final result = <ModelInfo>[];
    for (final item in models) {
      if (item is! Map) continue;
      final name = item['name'];
      if (name is! String || name.isEmpty) continue;
      final id =
          name.startsWith('models/') ? name.substring(7) : name;
      final methods = item['supportedGenerationMethods'];
      if (methods is List && methods.isNotEmpty) {
        final generative = methods.any(
          (m) => m == 'generateContent' || m == 'streamGenerateContent',
        );
        if (!generative) continue;
      }
      var displayName = id;
      final rawName = item['displayName'];
      if (rawName is String && rawName.trim().isNotEmpty) {
        displayName = rawName.trim();
      }
      int? contextWindow;
      final limit = item['inputTokenLimit'];
      if (limit is num) contextWindow = limit.toInt();
      result.add(ModelInfo(
        id: id,
        name: displayName,
        contextWindow: contextWindow,
        approximateContext: contextWindow == null,
        modalities: mediaModalitiesFor(id),
      ));
    }
    return result;
  }

  @override
  StreamDelta? parseStreamData(String data) {
    final text = data.trim();
    if (text.isEmpty) return const StreamDelta();
    final decoded = tryDecodeJson(text);
    if (decoded is! Map) return const StreamDelta();
    if (decoded['error'] != null) {
      final error = decoded['error'];
      final status =
          error is Map && error['code'] is int ? error['code'] as int : 400;
      throw ApiError.fromResponse(
        statusCode: status,
        body: text,
        format: ApiFormat.gemini,
      );
    }
    final feedback = decoded['promptFeedback'];
    if (feedback is Map && feedback['blockReason'] != null) {
      throw ApiError(
        type: ApiErrorType.invalidRequest,
        details: '${feedback['blockReason']}',
        raw: text,
      );
    }
    final meta = decoded['usageMetadata'];
    if (meta is Map) {
      final target = lastUsage ??= ChatUsage();
      if (meta['promptTokenCount'] is num) {
        target.inputTokens = (meta['promptTokenCount'] as num).toInt();
      }
      if (meta['candidatesTokenCount'] is num) {
        target.outputTokens = (meta['candidatesTokenCount'] as num).toInt();
      }
      if (meta['thoughtsTokenCount'] is num) {
        target.thinkingTokens = (meta['thoughtsTokenCount'] as num).toInt();
      }
    }
    final candidates = decoded['candidates'];
    if (candidates is List && candidates.isNotEmpty) {
      final first = candidates[0];
      if (first is Map) {
        final content = first['content'];
        if (content is Map && content['parts'] is List) {
          final textBuffer = StringBuffer();
          final thinkBuffer = StringBuffer();
          for (final part in content['parts'] as List) {
            if (part is Map && part['text'] is String) {
              if (part['thought'] == true) {
                thinkBuffer.write(part['text'] as String);
              } else {
                textBuffer.write(part['text'] as String);
              }
            }
          }
          return StreamDelta(
            text: textBuffer.toString(),
            reasoning: thinkBuffer.toString(),
          );
        }
      }
    }
    return const StreamDelta();
  }
}
