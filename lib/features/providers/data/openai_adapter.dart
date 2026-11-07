import '../../chat/domain/models.dart' as chat;
import '../../../core/errors/api_error.dart';
import '../../../core/network/api_format.dart';
import '../domain/model_info.dart';
import 'provider_adapter.dart';

class OpenAIAdapter extends ProviderAdapter {
  @override
  ApiFormat get format => ApiFormat.openai;

  @override
  ChatRequest buildChatRequest(ChatParams params) {
    final turns = ProviderAdapter.mergeTurns(params.turns);
    return ChatRequest(
      url: joinUrl(params.baseUrl, '/chat/completions'),
      headers: <String, String>{'Authorization': 'Bearer ${params.apiKey}'},
      body: <String, dynamic>{
        'model': params.model,
        'messages': <Map<String, dynamic>>[
          for (final turn in turns) _messageFor(turn),
        ],
        'stream': true,
        if (params.reasoningEffort != null)
          'reasoning_effort': params.reasoningEffort,
        if (params.maxTokens != null)
          if (isReasoningModel(params.model))
            'max_completion_tokens': params.maxTokens
          else
            'max_tokens': params.maxTokens,
      },
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
      content.add(_mediaPart(attachment));
    }
    return <String, dynamic>{'role': turn.role, 'content': content};
  }

  static Map<String, dynamic> _mediaPart(chat.ChatAttachment attachment) {
    final mime = attachment.mimeType.toLowerCase();
    if (mime.startsWith('image/')) {
      return <String, dynamic>{
        'type': 'image_url',
        'image_url': <String, dynamic>{
          'url': 'data:$mime;base64,${attachment.data}',
        },
      };
    }
    if (mime.startsWith('audio/')) {
      final format =
          mime == 'audio/wav' || mime == 'audio/x-wav' ? 'wav' : 'mp3';
      return <String, dynamic>{
        'type': 'input_audio',
        'input_audio': <String, dynamic>{
          'data': attachment.data,
          'format': format,
        },
      };
    }
    if (mime.startsWith('video/')) {
      return <String, dynamic>{
        'type': 'video_url',
        'video_url': <String, dynamic>{
          'url': 'data:$mime;base64,${attachment.data}',
        },
      };
    }
    return <String, dynamic>{
      'type': 'text',
      'text': '[attachment: ${attachment.name}]',
    };
  }

  @override
  ChatRequest buildModelsRequest({
    required String apiKey,
    required String baseUrl,
  }) {
    return ChatRequest(
      url: joinUrl(baseUrl, '/models'),
      headers: <String, String>{'Authorization': 'Bearer $apiKey'},
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
      if (item['archived'] == true) continue;
      var name = id;
      final rawName = item['name'];
      if (rawName is String && rawName.trim().isNotEmpty) {
        name = rawName.trim();
      }
      final declared = _declaredModalities(item);
      int? contextWindow;
      final rawContext = item['context_length'] ?? item['context_window'];
      if (rawContext is num) contextWindow = rawContext.toInt();
      double? inputPrice;
      double? outputPrice;
      final pricing = item['pricing'];
      if (pricing is Map) {
        // OpenRouter uses prompt/completion, Vercel AI Gateway input/output.
        inputPrice = pricePerMillion(pricing['prompt'] ?? pricing['input']);
        outputPrice =
            pricePerMillion(pricing['completion'] ?? pricing['output']);
      }
      result.add(ModelInfo(
        id: id,
        name: name,
        contextWindow: contextWindow,
        approximateContext: contextWindow == null,
        inputPricePerM: inputPrice,
        outputPricePerM: outputPrice,
        modalities: mediaModalitiesFor(id, declared: declared),
        reasoningEfforts: _reasoningEfforts(item),
      ));
    }
    return result;
  }

  static Set<ModelModality> _declaredModalities(Map item) {
    final out = <ModelModality>{};
    void addAll(Object? values) {
      if (values is! Iterable) return;
      for (final value in values) {
        switch ('$value'.toLowerCase()) {
          case 'image':
            out.add(ModelModality.image);
          case 'video':
            out.add(ModelModality.video);
          case 'audio':
            out.add(ModelModality.audio);
          default:
            break;
        }
      }
    }

    final modalities = item['modalities'];
    if (modalities is Map) {
      addAll(modalities['input']);
    } else if (modalities is Iterable) {
      addAll(modalities);
    }
    final architecture = item['architecture'];
    if (architecture is Map) {
      addAll(architecture['input_modalities']);
    }
    return out;
  }

  static List<String> _reasoningEfforts(Map item) {
    final out = <String>[];
    void addAll(Object? values) {
      if (values is! Iterable) return;
      for (final value in values) {
        final level = '$value';
        if (level.isNotEmpty && !out.contains(level)) out.add(level);
      }
    }

    final options = item['reasoning_options'];
    if (options is List) {
      for (final option in options) {
        if (option is Map && option['type'] == 'effort') {
          addAll(option['values']);
        }
      }
    }
    final reasoning = item['reasoning'];
    if (reasoning is Map) {
      addAll(reasoning['supported_efforts']);
    }
    return out;
  }

  @override
  String? parseStreamData(String data) {
    final text = data.trim();
    if (text.isEmpty) return '';
    if (text == '[DONE]') return null;
    final decoded = tryDecodeJson(text);
    if (decoded == null) return '';
    if (decoded is! Map) return '';
    if (decoded['error'] != null) {
      final error = decoded['error'];
      final status =
          error is Map && error['code'] is int ? error['code'] as int : 400;
      throw ApiError.fromResponse(
        statusCode: status,
        body: text,
        format: ApiFormat.openai,
      );
    }
    final usage = decoded['usage'];
    if (usage is Map) {
      final target = lastUsage ??= ChatUsage();
      if (usage['prompt_tokens'] is num) {
        target.inputTokens = (usage['prompt_tokens'] as num).toInt();
      }
      if (usage['completion_tokens'] is num) {
        target.outputTokens = (usage['completion_tokens'] as num).toInt();
      }
      final details = usage['completion_tokens_details'];
      if (details is Map && details['reasoning_tokens'] is num) {
        target.thinkingTokens = (details['reasoning_tokens'] as num).toInt();
      }
    }
    final choices = decoded['choices'];
    if (choices is List && choices.isNotEmpty) {
      final first = choices[0];
      if (first is Map) {
        final delta = first['delta'];
        if (delta is Map) {
          if (delta['content'] is String) {
            return delta['content'] as String;
          }
          final reasoning = delta['reasoning_content'] ?? delta['reasoning'];
          if (reasoning is String) {
            return reasoning;
          }
        }
        final legacy = first['text'];
        if (legacy is String) return legacy;
      }
    }
    return '';
  }
}
