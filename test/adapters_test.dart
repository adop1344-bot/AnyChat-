import 'dart:convert';
import 'dart:typed_data';

import 'package:anychat/core/errors/api_error.dart';
import 'package:anychat/core/network/api_format.dart';
import 'package:anychat/features/chat/domain/models.dart';
import 'package:anychat/features/providers/data/anthropic_adapter.dart';
import 'package:anychat/features/providers/data/gemini_adapter.dart';
import 'package:anychat/features/providers/data/openai_adapter.dart';
import 'package:anychat/features/providers/data/provider_adapter.dart';
import 'package:anychat/features/providers/domain/model_info.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// A dio transport stub: captures the outgoing request and replays a canned
/// response without touching the network.
class _FakeHttpAdapter implements HttpClientAdapter {
  _FakeHttpAdapter({required this.statusCode, required this.body});

  final int statusCode;
  final String body;
  RequestOptions? lastRequest;
  String? lastRequestBody;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastRequest = options;
    if (requestStream != null) {
      lastRequestBody = await utf8.decoder.bind(requestStream).join();
    }
    return ResponseBody.fromString(
      body,
      statusCode,
      headers: <String, List<String>>{
        'content-type': <String>['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Dio _dioWith(HttpClientAdapter adapter) => Dio()..httpClientAdapter = adapter;

ChatParams _params({
  String baseUrl = 'https://api.openai.com/v1',
  String model = 'gpt-4o-mini',
  int? maxTokens = 100,
  List<ChatTurn>? turns,
}) {
  return ChatParams(
    apiKey: 'sk-test-key',
    baseUrl: baseUrl,
    model: model,
    maxTokens: maxTokens,
    turns: turns ??
        const <ChatTurn>[
          ChatTurn(role: 'system', content: 'Be brief.'),
          ChatTurn(role: 'user', content: 'Hi'),
          ChatTurn(role: 'assistant', content: 'Hello'),
          ChatTurn(role: 'user', content: 'How are you?'),
        ],
  );
}

void main() {
  group('adapterFor', () {
    test('maps every wire format to its adapter', () {
      expect(adapterFor(ApiFormat.openai), isA<OpenAIAdapter>());
      expect(adapterFor(ApiFormat.anthropic), isA<AnthropicAdapter>());
      expect(adapterFor(ApiFormat.gemini), isA<GeminiAdapter>());
    });
  });

  group('OpenAIAdapter request building', () {
    final adapter = OpenAIAdapter();

    test('chat request url, headers and body', () {
      final request = adapter.buildChatRequest(_params());
      expect(request.url, 'https://api.openai.com/v1/chat/completions');
      expect(request.headers['Authorization'], 'Bearer sk-test-key');
      expect(request.body['model'], 'gpt-4o-mini');
      expect(request.body['stream'], isTrue);
      expect(request.body['max_tokens'], 100);
      final messages = request.body['messages'] as List<dynamic>;
      expect(messages, hasLength(4));
      expect((messages.first as Map<String, dynamic>)['role'], 'system');
    });

    test('trailing slash in base url is trimmed', () {
      final request = adapter.buildChatRequest(
        _params(baseUrl: 'https://api.openai.com/v1/'),
      );
      expect(request.url, 'https://api.openai.com/v1/chat/completions');
    });

    test('models request uses GET with bearer auth', () {
      final request = adapter.buildModelsRequest(
        apiKey: 'sk-test-key',
        baseUrl: 'https://api.openai.com/v1',
      );
      expect(request.url, 'https://api.openai.com/v1/models');
      expect(request.headers['Authorization'], 'Bearer sk-test-key');
    });

    test('builds openai multimodal content parts for attachments', () {
      final request = adapter.buildChatRequest(
        ChatParams(
          apiKey: 'k',
          baseUrl: 'https://api.openai.com/v1',
          model: 'gpt-4o',
          turns: const <ChatTurn>[
            ChatTurn(
              role: 'user',
              content: 'look at this',
              attachments: <ChatAttachment>[
                ChatAttachment(
                  mimeType: 'image/png',
                  name: 'a.png',
                  data: 'QUJD',
                ),
              ],
            ),
          ],
        ),
      );
      final messages = request.body['messages'] as List<dynamic>;
      final user = messages.first as Map<String, dynamic>;
      final content = user['content'] as List<dynamic>;
      expect(content, hasLength(2));
      expect(content[0],
          <String, dynamic>{'type': 'text', 'text': 'look at this'});
      final image = content[1] as Map<String, dynamic>;
      expect(image['type'], 'image_url');
      expect(
        (image['image_url'] as Map<String, dynamic>)['url'],
        'data:image/png;base64,QUJD',
      );
    });

    test('parses input modalities from gateway catalogs', () {
      final models = adapter.parseModels(
        '{"data":['
        '{"id":"openai/gpt-4o","modalities":{"input":["text","image"],"output":["text"]}},'
        '{"id":"meta-llama/llama-3.3-70b-instruct","architecture":{"input_modalities":["text"]}},'
        '{"id":"google/gemini-2.5-flash","modalities":{"input":["text","image"]}}]}',
      );
      expect(models, hasLength(3));
      expect(models[0].modalities, contains(ModelModality.image));
      expect(models[0].supportsAttachments, isTrue);
      expect(models[1].modalities, isEmpty);
      expect(models[1].supportsAttachments, isFalse);
      expect(
        models[2].modalities,
        containsAll(<ModelModality>[
          ModelModality.image,
          ModelModality.video,
          ModelModality.audio,
        ]),
      );
    });

    test('serializes reasoning_effort when set', () {
      final request = adapter.buildChatRequest(
        ChatParams(
          apiKey: 'k',
          baseUrl: 'https://api.openai.com/v1',
          model: 'o3-mini',
          turns: const <ChatTurn>[
            ChatTurn(role: 'user', content: 'think'),
          ],
          reasoningEffort: 'high',
        ),
      );
      expect(request.body['reasoning_effort'], 'high');
      final plain = adapter.buildChatRequest(
        ChatParams(
          apiKey: 'k',
          baseUrl: 'https://api.openai.com/v1',
          model: 'gpt-4o-mini',
          turns: const <ChatTurn>[
            ChatTurn(role: 'user', content: 'hi'),
          ],
        ),
      );
      expect(plain.body.containsKey('reasoning_effort'), isFalse);
    });

    test('captures usage and reasoning tokens from stream chunks', () {
      final adapter = OpenAIAdapter();
      adapter.parseStreamData(
        '{"choices":[],"usage":{"prompt_tokens":120,"completion_tokens":45,'
        '"completion_tokens_details":{"reasoning_tokens":12}}}',
      );
      expect(adapter.lastUsage?.inputTokens, 120);
      expect(adapter.lastUsage?.outputTokens, 45);
      expect(adapter.lastUsage?.thinkingTokens, 12);
    });

    test('parses thinking levels from gateway catalogs', () {
      final models = adapter.parseModels(
        '{"data":['
        '{"id":"a/qwen-3-32b","reasoning_options":[{"type":"toggle"},'
        '{"type":"effort","values":["none","low","medium","high"]}]},'
        '{"id":"m/kimi-k3","reasoning":{"supported_efforts":["max","high","low","none"]}},'
        '{"id":"plain/text","reasoning_options":[{"type":"budget_tokens","min":1,"max":81920}]}]}',
      );
      expect(models, hasLength(3));
      expect(
        models[0].reasoningEfforts,
        <String>['none', 'low', 'medium', 'high'],
      );
      expect(
        models[1].reasoningEfforts,
        containsAll(<String>['max', 'high', 'low', 'none']),
      );
      expect(models[2].reasoningEfforts, isEmpty);
    });

    test('parses Vercel AI Gateway style pricing and context window', () {
      final models = adapter.parseModels(
        '{"data":[{"id":"google/gemini-2.5-flash","name":"Gemini 2.5 Flash",'
        '"context_window":1000000,'
        '"pricing":{"input":"0.0000003","output":"0.0000025"}}]}',
      );
      expect(models, hasLength(1));
      expect(models.single.contextWindow, 1000000);
      expect(models.single.approximateContext, isFalse);
      expect(models.single.inputPricePerM, closeTo(0.3, 1e-9));
      expect(models.single.outputPricePerM, closeTo(2.5, 1e-9));
    });

    test('parses the models payload including pricing', () {
      final models = adapter.parseModels(
        '{"data":[{"id":"gpt-4o"},'
        '{"id":"gpt-4o-mini","context_length":128000,'
        '"pricing":{"prompt":"0.00000015","completion":"0.0000006"}},'
        '{"id":"archived-model","archived":true}]}',
      );
      expect(models, hasLength(2));
      expect(models.first.id, 'gpt-4o');
      expect(models.first.approximateContext, isTrue);
      expect(models[1].contextWindow, 128000);
      expect(models[1].approximateContext, isFalse);
      expect(models[1].inputPricePerM, closeTo(0.15, 1e-9));
      expect(models[1].outputPricePerM, closeTo(0.6, 1e-9));
    });
  });

  group('AnthropicAdapter request building', () {
    final adapter = AnthropicAdapter();

    test('chat request url, headers and body', () {
      final request = adapter.buildChatRequest(
        _params(baseUrl: 'https://api.anthropic.com/v1', model: 'claude-3-7-sonnet'),
      );
      expect(request.url, 'https://api.anthropic.com/v1/messages');
      expect(request.headers['x-api-key'], 'sk-test-key');
      expect(request.headers['anthropic-version'], '2023-06-01');
      expect(request.body['model'], 'claude-3-7-sonnet');
      expect(request.body['stream'], isTrue);
      expect(request.body['max_tokens'], 100);
      expect(request.body['system'], 'Be brief.');
      final messages = request.body['messages'] as List<dynamic>;
      expect(messages, hasLength(3));
      expect((messages.first as Map<String, dynamic>)['role'], 'user');
    });

    test('prompt caching marks system and stable prefix', () {
      final request = adapter.buildChatRequest(
        ChatParams(
          apiKey: 'k',
          baseUrl: 'https://api.anthropic.com/v1',
          model: 'claude-3-7-sonnet',
          maxTokens: 100,
          promptCaching: true,
          turns: const <ChatTurn>[
            ChatTurn(role: 'system', content: 'Be brief.'),
            ChatTurn(role: 'user', content: 'one'),
            ChatTurn(role: 'assistant', content: 'two'),
            ChatTurn(role: 'user', content: 'three'),
          ],
        ),
      );
      final system = request.body['system'] as List<dynamic>;
      expect(
        (system.single as Map<String, dynamic>)['cache_control'],
        <String, String>{'type': 'ephemeral'},
      );
      final messages = request.body['messages'] as List<dynamic>;
      expect(messages, hasLength(3));
      final stable = messages[1] as Map<String, dynamic>;
      final blocks = stable['content'] as List<dynamic>;
      expect(
        (blocks.single as Map<String, dynamic>)['cache_control'],
        <String, String>{'type': 'ephemeral'},
      );
      expect((messages.last as Map<String, dynamic>)['content'], 'three');
    });

    test('max_tokens defaults to 4096 when unset', () {
      final request = adapter.buildChatRequest(
        _params(
          baseUrl: 'https://api.anthropic.com/v1',
          model: 'claude-3-7-sonnet',
          maxTokens: null,
        ),
      );
      expect(request.body['max_tokens'], 4096);
    });

    test('models request carries anthropic headers', () {
      final request = adapter.buildModelsRequest(
        apiKey: 'sk-test-key',
        baseUrl: 'https://api.anthropic.com/v1',
      );
      expect(request.url, 'https://api.anthropic.com/v1/models');
      expect(request.headers['x-api-key'], 'sk-test-key');
      expect(request.headers['anthropic-version'], '2023-06-01');
    });

    test('parses the models payload', () {
      final models = adapter.parseModels(
        '{"data":[{"id":"claude-3-7-sonnet-latest","display_name":"Claude 3.7 Sonnet"}]}',
      );
      expect(models.single.id, 'claude-3-7-sonnet-latest');
      expect(models.single.name, 'Claude 3.7 Sonnet');
      expect(models.single.modalities, contains(ModelModality.image));
    });

    test('captures usage from anthropic stream events', () {
      final adapter = AnthropicAdapter();
      adapter.parseStreamData(
        '{"type":"message_start","message":{"usage":{"input_tokens":200}}}',
      );
      adapter.parseStreamData(
        '{"type":"message_delta","usage":{"output_tokens":64}}',
      );
      expect(adapter.lastUsage?.inputTokens, 200);
      expect(adapter.lastUsage?.outputTokens, 64);
    });

    test('builds anthropic base64 image parts', () {
      final request = adapter.buildChatRequest(
        ChatParams(
          apiKey: 'k',
          baseUrl: 'https://api.anthropic.com/v1',
          model: 'claude-3-7-sonnet',
          turns: const <ChatTurn>[
            ChatTurn(
              role: 'user',
              content: 'see this',
              attachments: <ChatAttachment>[
                ChatAttachment(
                  mimeType: 'image/jpeg',
                  name: 'b.jpg',
                  data: 'QUJD',
                ),
              ],
            ),
          ],
        ),
      );
      final messages = request.body['messages'] as List<dynamic>;
      final user = messages.first as Map<String, dynamic>;
      final content = user['content'] as List<dynamic>;
      expect(content, hasLength(2));
      final image = content[1] as Map<String, dynamic>;
      expect(image['type'], 'image');
      final source = image['source'] as Map<String, dynamic>;
      expect(source['type'], 'base64');
      expect(source['media_type'], 'image/jpeg');
      expect(source['data'], 'QUJD');
    });
  });

  group('GeminiAdapter request building', () {
    final adapter = GeminiAdapter();
    const baseUrl = 'https://generativelanguage.googleapis.com/v1beta';

    test('chat request url contains streaming and key', () {
      final request = adapter.buildChatRequest(
        _params(baseUrl: baseUrl, model: 'gemini-2.0-flash'),
      );
      expect(
        request.url,
        startsWith(
          'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:streamGenerateContent',
        ),
      );
      expect(request.url, contains('alt=sse'));
      expect(request.url, contains('key=sk-test-key'));
    });

    test('maps roles and system prompt into the gemini body', () {
      final request = adapter.buildChatRequest(
        _params(baseUrl: baseUrl, model: 'gemini-2.0-flash'),
      );
      expect(
        (request.body['systemInstruction'] as Map<String, dynamic>)['parts'],
        isNotEmpty,
      );
      final contents = request.body['contents'] as List<dynamic>;
      expect(contents, hasLength(3));
      expect((contents[0] as Map<String, dynamic>)['role'], 'user');
      expect((contents[1] as Map<String, dynamic>)['role'], 'model');
      final config = request.body['generationConfig'] as Map<String, dynamic>;
      expect(config['maxOutputTokens'], 100);
    });

    test('models request puts the key in the query', () {
      final request = adapter.buildModelsRequest(
        apiKey: 'AIza-Test_Key',
        baseUrl: baseUrl,
      );
      expect(request.url, '$baseUrl/models?key=AIza-Test_Key');
    });

    test('captures usage and thoughts from gemini usageMetadata', () {
      final adapter = GeminiAdapter();
      adapter.parseStreamData(
        '{"candidates":[],"usageMetadata":{"promptTokenCount":300,'
        '"candidatesTokenCount":50,"thoughtsTokenCount":90}}',
      );
      expect(adapter.lastUsage?.inputTokens, 300);
      expect(adapter.lastUsage?.outputTokens, 50);
      expect(adapter.lastUsage?.thinkingTokens, 90);
    });

    test('builds gemini inlineData parts for attachments', () {
      final request = adapter.buildChatRequest(
        ChatParams(
          apiKey: 'AIza-Test_Key',
          baseUrl: 'https://generativelanguage.googleapis.com/v1beta',
          model: 'gemini-2.5-flash',
          turns: const <ChatTurn>[
            ChatTurn(
              role: 'user',
              content: 'watch this',
              attachments: <ChatAttachment>[
                ChatAttachment(
                  mimeType: 'video/mp4',
                  name: 'v.mp4',
                  data: 'AAAA',
                ),
              ],
            ),
          ],
        ),
      );
      final contents = request.body['contents'] as List<dynamic>;
      final parts =
          (contents.first as Map<String, dynamic>)['parts'] as List<dynamic>;
      expect(parts, hasLength(2));
      expect(
        parts[1],
        <String, dynamic>{
          'inlineData': <String, dynamic>{'mimeType': 'video/mp4', 'data': 'AAAA'},
        },
      );
    });

    test('parses models and drops non-generative ones', () {
      final models = adapter.parseModels(
        '{"models":['
        '{"name":"models/gemini-2.0-flash","displayName":"Gemini 2.0 Flash",'
        '"supportedGenerationMethods":["generateContent","countTokens"],'
        '"inputTokenLimit":1048576},'
        '{"name":"models/text-embedding-004","displayName":"Embedding",'
        '"supportedGenerationMethods":["embedContent"]}]}',
      );
      expect(models, hasLength(1));
      expect(models.single.id, 'gemini-2.0-flash');
      expect(models.single.name, 'Gemini 2.0 Flash');
      expect(models.single.contextWindow, 1048576);
      expect(models.single.approximateContext, isFalse);
    });
  });

  group('parseStreamData', () {
    test('openai deltas and [DONE]', () {
      final adapter = OpenAIAdapter();
      expect(
        adapter.parseStreamData('{"choices":[{"delta":{"content":"Hi"}}]}'),
        'Hi',
      );
      expect(adapter.parseStreamData('[DONE]'), isNull);
      expect(adapter.parseStreamData(''), '');
    });

    test('openai in-stream error becomes ApiError', () {
      final adapter = OpenAIAdapter();
      expect(
        () => adapter.parseStreamData('{"error":{"code":429,"message":"slow"}}'),
        throwsA(
          isA<ApiError>().having((e) => e.type, 'type', ApiErrorType.rateLimit),
        ),
      );
    });

    test('anthropic deltas and stop event', () {
      final adapter = AnthropicAdapter();
      expect(
        adapter.parseStreamData(
          '{"type":"content_block_delta","delta":{"type":"text_delta","text":"ok"}}',
        ),
        'ok',
      );
      expect(adapter.parseStreamData('{"type":"message_stop"}'), isNull);
      expect(adapter.parseStreamData('{"type":"ping"}'), '');
    });

    test('anthropic error event maps kinds to statuses', () {
      final adapter = AnthropicAdapter();
      expect(
        () => adapter.parseStreamData(
          '{"type":"error","error":{"type":"rate_limit_error","message":"nope"}}',
        ),
        throwsA(
          isA<ApiError>().having((e) => e.type, 'type', ApiErrorType.rateLimit),
        ),
      );
      expect(
        () => adapter.parseStreamData(
          '{"type":"error","error":{"type":"overloaded_error","message":"busy"}}',
        ),
        throwsA(
          isA<ApiError>()
              .having((e) => e.type, 'type', ApiErrorType.serverError),
        ),
      );
    });

    test('gemini concatenates text parts', () {
      final adapter = GeminiAdapter();
      expect(
        adapter.parseStreamData(
          '{"candidates":[{"content":{"parts":[{"text":"He"},{"text":"llo"}]}}]}',
        ),
        'Hello',
      );
      expect(
        () => adapter.parseStreamData('{"promptFeedback":{"blockReason":"SAFETY"}}'),
        throwsA(isA<ApiError>()),
      );
    });
  });

  group('streamChat through dio', () {
    test('yields deltas from an SSE response', () async {
      final adapter = OpenAIAdapter();
      final fake = _FakeHttpAdapter(
        statusCode: 200,
        body: 'data: {"choices":[{"delta":{"content":"Hel"}}]}\n\n'
            'data: {"choices":[{"delta":{"content":"lo"}}]}\n\n'
            'data: [DONE]\n\n',
      );
      final dio = _dioWith(fake);

      final deltas =
          await adapter.streamChat(_params(), dio: dio).toList();

      expect(deltas, <String>['Hel', 'lo']);
      expect(
        fake.lastRequest!.uri.toString(),
        'https://api.openai.com/v1/chat/completions',
      );
      expect(fake.lastRequest!.headers['Authorization'], 'Bearer sk-test-key');
      final sent = jsonDecode(fake.lastRequestBody!) as Map<String, dynamic>;
      expect(sent['model'], 'gpt-4o-mini');
      expect(sent['stream'], isTrue);
      expect((sent['messages'] as List).length, 4);
    });

    test('non-2xx response throws a normalized ApiError', () async {
      final adapter = OpenAIAdapter();
      final fake = _FakeHttpAdapter(
        statusCode: 401,
        body: '{"error":{"message":"bad key","code":"invalid_api_key"}}',
      );
      expect(
        () => adapter.streamChat(_params(), dio: _dioWith(fake)).toList(),
        throwsA(
          isA<ApiError>().having((e) => e.type, 'type', ApiErrorType.authError),
        ),
      );
    });
  });

  group('fetchModels through dio', () {
    test('parses a successful response', () async {
      final adapter = OpenAIAdapter();
      final fake = _FakeHttpAdapter(
        statusCode: 200,
        body: '{"data":[{"id":"gpt-4o-mini","context_length":128000}]}',
      );
      final models = await adapter.fetchModels(
        apiKey: 'sk-test-key',
        baseUrl: 'https://api.openai.com/v1',
        dio: _dioWith(fake),
      );
      expect(models.single.id, 'gpt-4o-mini');
      expect(
        fake.lastRequest!.uri.toString(),
        'https://api.openai.com/v1/models',
      );
      expect(fake.lastRequest!.headers['Authorization'], 'Bearer sk-test-key');
    });

    test('error status throws mapped ApiError', () async {
      final adapter = OpenAIAdapter();
      final fake = _FakeHttpAdapter(
        statusCode: 401,
        body: '{"error":{"message":"bad key"}}',
      );
      expect(
        () => adapter.fetchModels(
          apiKey: 'sk-test-key',
          baseUrl: 'https://api.openai.com/v1',
          dio: _dioWith(fake),
        ),
        throwsA(
          isA<ApiError>().having((e) => e.type, 'type', ApiErrorType.authError),
        ),
      );
    });
  });

  group('ProviderAdapter helpers', () {
    test('mergeTurns joins adjacent same-role turns and drops empties', () {
      final merged = ProviderAdapter.mergeTurns(const <ChatTurn>[
        ChatTurn(role: 'system', content: 'a'),
        ChatTurn(role: 'system', content: 'b'),
        ChatTurn(role: 'user', content: ''),
        ChatTurn(role: 'user', content: 'hi'),
        ChatTurn(role: 'assistant', content: 'yo'),
      ]);
      expect(merged, hasLength(3));
      expect(merged[0].content, 'a\n\nb');
      expect(merged[1].content, 'hi');
      expect(merged[2].role, 'assistant');
    });

    test('mergeTurns keeps attachments of media-only turns', () {
      final merged = ProviderAdapter.mergeTurns(const <ChatTurn>[
        ChatTurn(
          role: 'user',
          content: '',
          attachments: <ChatAttachment>[
            ChatAttachment(mimeType: 'image/png', name: 'a.png', data: 'QQ=='),
          ],
        ),
        ChatTurn(role: 'user', content: 'hi'),
      ]);
      expect(merged, hasLength(1));
      expect(merged.single.content, 'hi');
      expect(merged.single.attachments, hasLength(1));
      expect(merged.single.attachments.single.name, 'a.png');
    });

    test('systemPromptOf concatenates system turns', () {
      final system = ProviderAdapter.systemPromptOf(const <ChatTurn>[
        ChatTurn(role: 'system', content: 'one'),
        ChatTurn(role: 'user', content: 'x'),
        ChatTurn(role: 'system', content: 'two'),
      ]);
      expect(system, 'one\n\ntwo');
      expect(
        ProviderAdapter.systemPromptOf(const <ChatTurn>[
          ChatTurn(role: 'user', content: 'x'),
        ]),
        isNull,
      );
    });
  });
}
