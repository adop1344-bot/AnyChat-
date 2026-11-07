import '../../../core/errors/api_error.dart';
import '../../../core/network/api_format.dart';
import '../domain/model_info.dart';
import 'provider_adapter.dart';

class AnthropicAdapter extends ProviderAdapter {
  static const Map<String, int> _errorStatus = <String, int>{
    'rate_limit_error': 429,
    'authentication_error': 401,
    'permission_error': 403,
    'not_found_error': 404,
    'overloaded_error': 529,
    'api_error': 500,
    'invalid_request_error': 400,
  };

  @override
  ApiFormat get format => ApiFormat.anthropic;

  @override
  ChatRequest buildChatRequest(ChatParams params) {
    final turns = ProviderAdapter.mergeTurns(params.turns);
    final system = ProviderAdapter.systemPromptOf(turns);
    final messages = turns.where((t) => t.role != 'system').toList();
    final messageMaps = <Map<String, dynamic>>[
      for (final turn in messages) _messageFor(turn),
    ];
    if (params.promptCaching && messageMaps.length >= 2) {
      _markCacheBreakpoint(messageMaps[messageMaps.length - 2]);
    }
    final body = <String, dynamic>{
      'model': params.model,
      'max_tokens': params.maxTokens ?? 4096,
      'stream': true,
      'messages': messageMaps,
    };
    if (system != null) {
      if (params.promptCaching) {
        body['system'] = <Map<String, dynamic>>[
          <String, dynamic>{
            'type': 'text',
            'text': system,
            'cache_control': <String, String>{'type': 'ephemeral'},
          },
        ];
      } else {
        body['system'] = system;
      }
    }
    return ChatRequest(
      url: joinUrl(params.baseUrl, '/messages'),
      headers: <String, String>{
        'x-api-key': params.apiKey,
        'anthropic-version': '2023-06-01',
      },
      body: body,
    );
  }

  static Map<String, dynamic> _messageFor(ChatTurn turn) {
    if (turn.attachments.isEmpty) {
      return <String, dynamic>{'role': turn.role, 'content': turn.content};
    }
    final content = <Map<String, dynamic>>[];
    if (turn.content.isNotEmpty) {
      content.add(<String, dynamic>{'type': 'text', 'text': turn.content});
    }
    for (final attachment in turn.attachments) {
      if (!attachment.isImage) {
        content.add(<String, dynamic>{
          'type': 'text',
          'text': '[attachment: ${attachment.name}]',
        });
        continue;
      }
      content.add(<String, dynamic>{
        'type': 'image',
        'source': <String, dynamic>{
          'type': 'base64',
          'media_type': attachment.mimeType,
          'data': attachment.data,
        },
      });
    }
    if (content.isEmpty) {
      final text = turn.content.isEmpty ? '(empty)' : turn.content;
      content.add(<String, dynamic>{'type': 'text', 'text': text});
    }
    return <String, dynamic>{'role': turn.role, 'content': content};
  }

  static void _markCacheBreakpoint(Map<String, dynamic> message) {
    final content = message['content'];
    if (content is List && content.isNotEmpty) {
      final last = content.last;
      if (last is Map<String, dynamic>) {
        last['cache_control'] = <String, String>{'type': 'ephemeral'};
      }
      return;
    }
    if (content is String) {
      message['content'] = <Map<String, dynamic>>[
        <String, dynamic>{
          'type': 'text',
          'text': content,
          'cache_control': <String, String>{'type': 'ephemeral'},
        },
      ];
    }
  }

  @override
  ChatRequest buildModelsRequest({
    required String apiKey,
    required String baseUrl,
  }) {
    return ChatRequest(
      url: joinUrl(baseUrl, '/models'),
      headers: <String, String>{
        'x-api-key': apiKey,
        'anthropic-version': '2023-06-01',
      },
      body: const <String, dynamic>{},
    );
  }

  @override
  List<ModelInfo> parseModels(String jsonBody) {
    final decoded = tryDecodeJson(jsonBody);
    if (decoded is! Map) return const <ModelInfo>[];
    final data = decoded['data'];
    if (data is! List) return const <ModelInfo>[];
    final result = <ModelInfo>[];
    for (final item in data) {
      if (item is! Map) continue;
      final id = item['id'];
      if (id is! String || id.isEmpty) continue;
      var name = id;
      final rawName = item['display_name'];
      if (rawName is String && rawName.trim().isNotEmpty) {
        name = rawName.trim();
      }
      result.add(
        ModelInfo(
          id: id,
          name: name,
          approximateContext: true,
          modalities: mediaModalitiesFor(id),
        ),
      );
    }
    return result;
  }

  @override
  String? parseStreamData(String data) {
    final text = data.trim();
    if (text.isEmpty) return '';
    final decoded = tryDecodeJson(text);
    if (decoded is! Map) return '';
    final type = decoded['type'];
    if (type == 'error') {
      final error = decoded['error'];
      final errorKind = error is Map ? '${error['type'] ?? ''}' : '';
      throw ApiError.fromResponse(
        statusCode: _errorStatus[errorKind] ?? 400,
        body: text,
        format: ApiFormat.anthropic,
      );
    }
    if (type == 'message_start') {
      final message = decoded['message'];
      final usage = message is Map ? message['usage'] : null;
      if (usage is Map && usage['input_tokens'] is num) {
        final target = lastUsage ??= ChatUsage();
        target.inputTokens = (usage['input_tokens'] as num).toInt();
      }
      return '';
    }
    if (type == 'message_delta') {
      final usage = decoded['usage'];
      if (usage is Map && usage['output_tokens'] is num) {
        final target = lastUsage ??= ChatUsage();
        target.outputTokens = (usage['output_tokens'] as num).toInt();
      }
      return '';
    }
    if (type == 'message_stop') return null;
    if (type == 'content_block_delta') {
      final delta = decoded['delta'];
      if (delta is Map && delta['text'] is String) {
        return delta['text'] as String;
      }
    }
    return '';
  }
}
