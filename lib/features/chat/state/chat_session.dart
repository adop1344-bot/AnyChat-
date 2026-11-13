import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../app_providers.dart';
import '../../../core/errors/api_error.dart';
import '../../../core/network/stream_guard.dart';
import '../../../core/network/think_splitter.dart';
import '../../../core/web/web_search.dart';
import '../../../core/storage/token_estimator.dart';
import '../../../core/errors/debug_log.dart';
import '../../../features/providers/data/provider_adapter.dart';
import '../../settings/app_settings.dart';
import '../../../core/tools/termux_shell.dart';
import '../../settings/state/settings_controller.dart';
import '../data/widget_repository.dart';
import '../domain/models.dart';

part 'chat_session.g.dart';

enum ChatIssue { noKey, noModel, noChat, noProvider }

class ChatSessionState {
  const ChatSessionState({
    this.isStreaming = false,
    this.streamingChatId,
    this.streamingMessageId,
    this.streamText = '',
    this.streamReasoning = '',
    this.busy = false,
    this.lastError,
    this.lastIssue,
    this.toolNotice = '',
    this.streamToolSteps = const <ToolStep>[],
  });

  final bool isStreaming;
  final int? streamingChatId;
  final int? streamingMessageId;
  final String streamText;
  final String streamReasoning;
  final bool busy;
  final ApiError? lastError;
  final ChatIssue? lastIssue;

  final String toolNotice;

  final List<ToolStep> streamToolSteps;

  bool get hasFailure => lastError != null || lastIssue != null;
}

class _Session {
  const _Session({
    required this.chat,
    required this.branchId,
    required this.settings,
    required this.adapter,
    required this.apiKey,
    required this.baseUrl,
    required this.model,
  });

  final Chat chat;
  final int branchId;
  final AppSettings settings;
  final ProviderAdapter adapter;
  final String apiKey;
  final String baseUrl;
  final String model;

  _Session withBranch(int branchId) => _Session(
        chat: chat,
        branchId: branchId,
        settings: settings,
        adapter: adapter,
        apiKey: apiKey,
        baseUrl: baseUrl,
        model: model,
      );
}

/// Keep-alive so an in-flight generation survives navigation.
@Riverpod(keepAlive: true)
class ChatSession extends _$ChatSession {
  CancelToken? _token;

  @override
  ChatSessionState build() => const ChatSessionState();

  Future<void> send(
    int chatId,
    String text, {
    List<ChatAttachment> attachments = const <ChatAttachment>[],
  }) async {
    final trimmed = text.trim();
    if ((trimmed.isEmpty && attachments.isEmpty) ||
        state.isStreaming ||
        state.busy) {
      return;
    }

    final command = RegExp(r'^/(\w+)\s*(.*)$').firstMatch(trimmed);
    var forceWeb = false;
    var endMode = false;
    if (command != null) {
      final name = command.group(1)!.toLowerCase();
      final rest = command.group(2)!.trim();
      switch (name) {
        case 'stop':
          stop();
          return;
        case 'help':
          await _localReply(chatId, trimmed, _helpText());
          return;
        case 'widget':
          if (rest.isEmpty) {
            await _localReply(
              chatId,
              trimmed,
              'Опиши, какой виджет создать, например:\n'
                  '/widget счётчик выпитой воды\n'
                  '/widget заметка со списком покупок\n'
                  '/widget чек-лист дел на день',
            );
            return;
          }
        case 'search':
          if (rest.isEmpty) {
            await _localReply(
              chatId,
              trimmed,
              'Укажи запрос: /search что искать',
            );
            return;
          }
          forceWeb = true;
        case 'end':
          endMode = true;
      }
    }

    state = const ChatSessionState();

    final session = await _openSession(chatId);
    if (session == null) return;

    final repo = ref.read(messageRepositoryProvider);
    final history = await repo.messagesInBranch(session.branchId);
    final isFirstUserMessage = !history.any((m) => m.role == 'user');
    await repo.insertMessage(
      chatId: chatId,
      branchId: session.branchId,
      role: 'user',
      content: trimmed,
      attachments: Message.encodeAttachments(attachments),
    );
    if (isFirstUserMessage) {
      await ref
          .read(chatRepositoryProvider)
          .renameChat(chatId, deriveChatTitle(trimmed));
    }

    final fresh = await repo.messagesInBranch(session.branchId);
    await _generate(
      session: session,
      turns: _historyTurns(session, fresh),
      forceWeb: forceWeb,
      endMode: endMode,
    );
  }

  Future<void> _localReply(int chatId, String userText, String reply) async {
    final session = await _openSession(chatId);
    if (session == null) return;
    final repo = ref.read(messageRepositoryProvider);
    await repo.insertMessage(
      chatId: chatId,
      branchId: session.branchId,
      role: 'user',
      content: userText,
    );
    await repo.insertMessage(
      chatId: chatId,
      branchId: session.branchId,
      role: 'assistant',
      content: reply,
      model: session.model,
    );
  }

  static String _helpText() =>
      'Команды:\n'
      '/widget <описание> — создать виджет в этом чате (ИИ уточнит детали)\n'
      '/search <запрос> — поиск в интернете для одного ответа\n'
      '/end <задача> — автономный режим: ИИ работает, пока полностью не '
      'завершит задачу\n'
      '/stop — остановить генерацию\n'
      '/help — эта справка';

  var _stopRequested = false;

  void stop() {
    _stopRequested = true;
    final token = _token;
    if (token != null && !token.isCancelled) {
      token.cancel();
    }
  }

  Future<void> regenerate(int chatId, {int? targetMessageId}) async {
    if (state.isStreaming || state.busy) return;
    state = const ChatSessionState();
    final session = await _openSession(chatId);
    if (session == null) return;
    try {
      final repo = ref.read(messageRepositoryProvider);
      final history = await repo.messagesInBranch(session.branchId);
      if (history.isEmpty) return;
      var targetId = targetMessageId;
      if (targetId != null && !history.any((Message m) => m.id == targetId)) {
        targetId = null;
      }
      if (targetId == null && history.last.role == 'assistant') {
        targetId = history.last.id;
      }
      if (targetId != null) {
        final chatRepo = ref.read(chatRepositoryProvider);
        final branches = await chatRepo.getBranches(chatId);
        final newBranchId = await chatRepo.forkBranchBefore(
          chatId: chatId,
          sourceBranchId: session.branchId,
          messageId: targetId,
          name: 'v${branches.length + 1}',
        );
        final freshSession = session.withBranch(newBranchId);
        final freshHistory = await repo.messagesInBranch(newBranchId);
        if (freshHistory.isEmpty) return;
        await _generate(
          session: freshSession,
          turns: _historyTurns(freshSession, freshHistory),
        );
        return;
      }
      await _generate(session: session, turns: _historyTurns(session, history));
    } catch (e) {
      _setUnknownFailure(e);
    }
  }

  Future<int?> branchFrom(int chatId, int messageId) async {
    if (state.isStreaming || state.busy) return null;
    state = const ChatSessionState();
    final session = await _openSession(chatId);
    if (session == null) return null;
    try {
      final chatRepo = ref.read(chatRepositoryProvider);
      final branches = await chatRepo.getBranches(chatId);
      return await chatRepo.forkBranchFrom(
        chatId: chatId,
        sourceBranchId: session.branchId,
        messageId: messageId,
        name: 'v${branches.length + 1}',
      );
    } catch (e) {
      _setUnknownFailure(e);
      return null;
    }
  }

  Future<void> editMessage(int chatId, int messageId, String newText) async {
    final trimmed = newText.trim();
    if (trimmed.isEmpty || state.isStreaming || state.busy) return;
    state = const ChatSessionState();
    final session = await _openSession(chatId);
    if (session == null) return;
    try {
      final chatRepo = ref.read(chatRepositoryProvider);
      final msgRepo = ref.read(messageRepositoryProvider);
      final branches = await chatRepo.getBranches(chatId);
      final newBranchId = await chatRepo.forkBranchBefore(
        chatId: chatId,
        sourceBranchId: session.branchId,
        messageId: messageId,
        name: 'v${branches.length + 1}',
      );
      await msgRepo.insertMessage(
        chatId: chatId,
        branchId: newBranchId,
        role: 'user',
        content: trimmed,
      );
      final history = await msgRepo.messagesInBranch(newBranchId);
      final newSession = session.withBranch(newBranchId);
      await _generate(session: newSession, turns: _historyTurns(newSession, history));
    } catch (e) {
      _setUnknownFailure(e);
    }
  }

  Future<void> switchBranch(int chatId, int branchId) async {
    if (state.isStreaming || state.busy) return;
    state = const ChatSessionState();
    await ref.read(chatRepositoryProvider).setActiveBranch(chatId, branchId);
  }

  Future<int?> summarize(int chatId, {required String prompt}) async {
    if (state.isStreaming || state.busy) return null;
    final trimmedPrompt = prompt.trim();
    if (trimmedPrompt.isEmpty) return null;
    state = const ChatSessionState();

    final session = await _openSession(chatId);
    if (session == null) return null;

    final msgRepo = ref.read(messageRepositoryProvider);
    final history = await msgRepo.messagesInBranch(session.branchId);
    if (history.isEmpty) return null;

    state = const ChatSessionState(busy: true);
    final token = CancelToken();
    _token = token;
    try {
      final turns = <ChatTurn>[
        ..._historyTurns(session, history, withAttachments: false),
        ChatTurn(role: 'user', content: trimmedPrompt),
      ];
      final params = ChatParams(
        apiKey: session.apiKey,
        baseUrl: session.baseUrl,
        model: session.model,
        turns: turns,
        reasoningEffort: session.settings.reasoningEffort.isEmpty
            ? null
            : session.settings.reasoningEffort,
        maxTokens: session.settings.maxTokens,
        promptCaching: session.settings.promptCaching,
        timeout: Duration(seconds: session.settings.timeoutSeconds),
      );
      final buffer = StringBuffer();
      await for (final delta
          in session.adapter.streamChat(params, cancelToken: token)) {
        buffer.write(delta.text);
      }
      final summary = buffer.toString().trim();
      if (summary.isEmpty) {
        state = const ChatSessionState();
        return null;
      }
      final chatRepo = ref.read(chatRepositoryProvider);
      final created = await chatRepo.createChat(
        title: deriveChatTitle(summary),
      );
      await msgRepo.insertMessage(
        chatId: created.chatId,
        branchId: created.branchId,
        role: 'system',
        content: summary,
      );
      state = const ChatSessionState();
      return created.chatId;
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        state = const ChatSessionState();
        return null;
      }
      final error = ApiError.fromDio(e, session.adapter.format);
      ref.read(debugLogProvider.notifier).add(error);
      state = ChatSessionState(lastError: error);
      return null;
    } on ApiError catch (error) {
      ref.read(debugLogProvider.notifier).add(error);
      state = ChatSessionState(lastError: error);
      return null;
    } catch (e) {
      _setUnknownFailure(e);
      return null;
    } finally {
      _token = null;
    }
  }

  Future<_Session?> _openSession(int chatId) async {
    final chatRepo = ref.read(chatRepositoryProvider);
    final chat = await chatRepo.getChat(chatId);
    if (chat == null) {
      state = const ChatSessionState(lastIssue: ChatIssue.noChat);
      return null;
    }
    final branchId = await chatRepo.ensureActiveBranch(chatId, chat);

    final settings = await ref.read(settingsControllerProvider.future);
    final provider = await ref
        .read(providerConfigRepositoryProvider)
        .getProvider(settings.selectedProviderId);
    if (provider == null) {
      state = const ChatSessionState(lastIssue: ChatIssue.noProvider);
      return null;
    }
    final model = settings.selectedModelId ?? '';
    if (model.trim().isEmpty) {
      state = const ChatSessionState(lastIssue: ChatIssue.noModel);
      return null;
    }
    final key = await ref.read(keyStoreProvider).readKey(provider.id);
    if (key == null || key.trim().isEmpty) {
      state = const ChatSessionState(lastIssue: ChatIssue.noKey);
      return null;
    }
    return _Session(
      chat: chat,
      branchId: branchId,
      settings: settings,
      adapter: adapterFor(provider.format),
      apiKey: key.trim(),
      baseUrl: provider.baseUrl,
      model: model,
    );
  }

  ChatTurn? _systemTurnFor(_Session session) {
    final chatPrompt = session.chat.systemPrompt;
    final source = (chatPrompt != null && chatPrompt.trim().isNotEmpty)
        ? chatPrompt
        : session.settings.systemPrompt;
    final trimmed = source.trim();
    return trimmed.isEmpty ? null : ChatTurn(role: 'system', content: trimmed);
  }

  List<ChatTurn> _historyTurns(
    _Session session,
    List<Message> history, {
    bool withAttachments = true,
  }) {
    final system = _systemTurnFor(session);
    var source = history;
    final depth = session.settings.historyDepth;
    if (depth != null && depth > 0 && source.length > depth) {
      source = source.sublist(source.length - depth);
    }
    return <ChatTurn>[
      ?system,
      for (final message in source)
        if ((message.role == 'user' || message.role == 'assistant') &&
            (message.content.trim().isNotEmpty ||
                message.attachments.isNotEmpty))
          ChatTurn(
            role: message.role,
            content: ThinkSplitter.stripThink(message.content),
            attachments: withAttachments
                ? message.attachments
                : const <ChatAttachment>[],
          ),
    ];
  }

  Future<void> _generate({
    required _Session session,
    required List<ChatTurn> turns,
    bool forceWeb = false,
    bool endMode = false,
  }) async {
    if (turns.isEmpty) return;
    _stopRequested = false;
    final repo = ref.read(messageRepositoryProvider);
    final assistantId = await repo.insertMessage(
      chatId: session.chat.id,
      branchId: session.branchId,
      role: 'assistant',
      content: '',
      model: session.model,
    );
    final webEnabled = session.settings.webSearch || forceWeb;
    final widgetMode = turns
        .where((ChatTurn t) => t.role == 'user')
        .toList()
        .reversed
        .take(6)
        .any((ChatTurn t) => t.content.trim().startsWith('/widget'));
    var webTurns = turns;
    if (webEnabled) {
      webTurns = _withWebHint(webTurns);
    }
    if (widgetMode) {
      webTurns = _withWidgetHint(webTurns);
    }
    if (endMode) {
      webTurns = _withEndHint(webTurns);
    }
    final shellEnabled = session.settings.agentShell;
    if (shellEnabled) {
      webTurns = _withShellHint(webTurns);
    }
    const doneMarker = '[DONE]';
    const maxToolRounds = 6;
    const maxEndRounds = 8;
    var content = '';
    var reasoning = '';
    var rounds = 0;
    var endRounds = 0;
    final steps = <ToolStep>[];
    await StreamGuard.begin();
    try {
      while (true) {
        while (true) {
          content = await _streamAttempt(
            session: session,
            turns: webTurns,
            assistantId: assistantId,
            attempt: 0,
            seedContent: content,
            seedReasoning: reasoning,
          );
          if (_stopRequested || state.lastError != null) break;
          if (rounds >= maxToolRounds) break;
          final tool = WebToolCall.extract(content);
          if (tool == null) break;
          final visible = content.substring(0, tool.start).trimRight();
          content = visible;
          await repo.setContent(assistantId, visible);

          if (tool.kind == 'WIDGET') {
            final summary = await _createWidget(session, tool.argument);
            steps.add(
              ToolStep(kind: 'WIDGET', argument: 'виджет', summary: summary),
            );
            await repo.setToolSteps(assistantId, steps);
            state = ChatSessionState(
              isStreaming: true,
              streamingChatId: session.chat.id,
              streamingMessageId: assistantId,
              streamText: visible,
              streamReasoning: reasoning,
              streamToolSteps: steps,
            );
            webTurns = <ChatTurn>[
              ...webTurns,
              ChatTurn(role: 'assistant', content: visible),
              ChatTurn(
                role: 'user',
                content: summary.startsWith('Виджет')
                    ? 'Widget created OK. Кратко подтверди пользователю '
                        'на его языке, не выводи строку WIDGET.'
                    : 'Widget failed: $summary. Скажи об этом пользователю '
                        'коротко на его языке.',
              ),
            ];
            rounds++;
            continue;
          }

          if (tool.kind == 'RUN') {
            if (!shellEnabled) {
              steps.add(
                ToolStep(
                  kind: 'RUN',
                  argument: tool.argument,
                  summary: 'инструмент выключен',
                ),
              );
              await repo.setToolSteps(assistantId, steps);
              webTurns = <ChatTurn>[
                ...webTurns,
                ChatTurn(role: 'assistant', content: visible),
                ChatTurn(
                  role: 'user',
                  content: 'Shell tool is disabled. Продолжай без команд, '
                      'не выводи строку RUN.',
                ),
              ];
              rounds++;
              continue;
            }
            state = ChatSessionState(
              isStreaming: true,
              streamingChatId: session.chat.id,
              streamingMessageId: assistantId,
              streamText: visible,
              streamReasoning: reasoning,
              streamToolSteps: steps,
              toolNotice: '⌨️ Команда: ${tool.argument}',
            );
            final result =
                TermuxShell.trimResult(await TermuxShell.run(tool.argument));
            if (_stopRequested) break;
            final oneLine = result.replaceAll('\n', ' ');
            steps.add(
              ToolStep(
                kind: 'RUN',
                argument: tool.argument,
                summary: oneLine.length > 60
                    ? '${oneLine.substring(0, 60)}…'
                    : oneLine,
              ),
            );
            await repo.setToolSteps(assistantId, steps);
            webTurns = <ChatTurn>[
              ...webTurns,
              ChatTurn(role: 'assistant', content: visible),
              ChatTurn(
                role: 'user',
                content: 'SHELL RESULT (exit code in first line):\n'
                    '$result\n\n'
                    'Продолжай на языке пользователя; при необходимости '
                    'следующая RUN: — по одной. Служебные строки не выводи.',
              ),
            ];
            rounds++;
            continue;
          }

          if (!webEnabled) {
            steps.add(
              ToolStep(
                kind: tool.kind,
                argument: tool.argument,
                summary: 'инструменты выключены',
              ),
            );
            await repo.setToolSteps(assistantId, steps);
            webTurns = <ChatTurn>[
              ...webTurns,
              ChatTurn(role: 'assistant', content: visible),
              ChatTurn(
                role: 'user',
                content: 'Web tools are disabled. Продолжай ответ без них, '
                    'не выводи строки SEARCH/OPEN.',
              ),
            ];
            rounds++;
            continue;
          }

          state = ChatSessionState(
            isStreaming: true,
            streamingChatId: session.chat.id,
            streamingMessageId: assistantId,
            streamText: visible,
            streamReasoning: reasoning,
            streamToolSteps: steps,
            toolNotice: tool.kind == 'OPEN'
                ? '📖 Читаю страницу…'
                : '🔍 Ищу: ${tool.argument}',
          );
          final result = await WebSearch.run(tool);
          if (_stopRequested) break;
          final oneLine = result.replaceAll('\n', ' ');
          steps.add(
            ToolStep(
              kind: tool.kind,
              argument: tool.argument,
              summary: oneLine.length > 60
                  ? '${oneLine.substring(0, 60)}…'
                  : oneLine,
            ),
          );
          await repo.setToolSteps(assistantId, steps);
          state = ChatSessionState(
            isStreaming: true,
            streamingChatId: session.chat.id,
            streamingMessageId: assistantId,
            streamText: visible,
            streamReasoning: reasoning,
            streamToolSteps: steps,
          );
          webTurns = <ChatTurn>[
            ...webTurns,
            ChatTurn(role: 'assistant', content: visible),
            ChatTurn(
              role: 'user',
              content: '$result\n\nИспользуй эти данные и продолжай ответ '
                  'пользователю на его языке. Не повторяй уже написанное и не '
                  'выводи служебные строки SEARCH/OPEN/WIDGET.',
            ),
          ];
          rounds++;
        }

        if (!endMode || _stopRequested || state.lastError != null) break;
        final markerIndex = content.indexOf(doneMarker);
        if (markerIndex >= 0) {
          content = content.substring(0, markerIndex).trimRight();
          await repo.setContent(assistantId, content);
          break;
        }
        if (endRounds >= maxEndRounds) break;
        endRounds++;
        webTurns = <ChatTurn>[
          ...webTurns,
          ChatTurn(role: 'assistant', content: content),
          ChatTurn(
            role: 'user',
            content: 'Continue the task exactly from where you stopped, '
                'do not repeat yourself. When the ENTIRE task is fully '
                'complete, output $doneMarker on its own final line.',
          ),
        ];
      }
    } finally {
      await StreamGuard.end();
    }
  }

  Future<String> _createWidget(_Session session, String argument) async {
    try {
      final decoded = jsonDecode(argument);
      if (decoded is Map<String, dynamic>) {
        final type = (decoded['type'] ?? '').toString();
        final title = (decoded['title'] ?? '').toString();
        final cfg = decoded['config'];
        final config =
            cfg is Map<String, dynamic> ? cfg : <String, dynamic>{};
        if (!ChatWidget.knownTypes.contains(type)) {
          return 'Неизвестный тип виджета: $type';
        }
        await ref.read(widgetRepositoryProvider).insert(
              chatId: session.chat.id,
              type: type,
              title: title,
              config: config,
            );
        return 'Виджет «$title» создан';
      }
      return 'Некорректный JSON виджета';
    } on FormatException {
      return 'Некорректный JSON виджета';
    }
  }

  List<ChatTurn> _withWidgetHint(List<ChatTurn> turns) {
    const hint =
        '\n\nWIDGET: output one line '
        'WIDGET: {"type":"counter|note|todo","title":"…","config":{…}} '
        '(counter {"value":int,"step":int,"unit":str}, note {"text":str}, '
        'todo {"items":[{"text":str,"done":bool}]}). '
        'One short question only if critical.';
    return _appendSystem(turns, hint);
  }

  List<ChatTurn> _withShellHint(List<ChatTurn> turns) {
    const hint =
        '\n\nSHELL: you may run a command on the user\'s phone via '
        'Termux: output RUN: <command> and stop — the result with exit '
        'code arrives as the next message. Multi-line commands and '
        'heredocs are allowed; to save a file use '
        'RUN: cat > /path <<\'EOF\' … EOF. Non-interactive, under 2 '
        'minutes, nothing destructive unless asked. Use only when the '
        'task truly needs it — never for greetings or chat. '
        'Always reply in the user\'s language.';
    return _appendSystem(turns, hint);
  }

  List<ChatTurn> _withEndHint(List<ChatTurn> turns) {
    final hint =
        '\n\nTASK MODE (/end): the user gave you a task and wants you to '
        'work autonomously until it is FULLY complete. After each part you '
        'will be told to continue — keep going without repeating yourself. '
        'When the entire task is finished, output [DONE] on its own '
        'final line.';
    return _appendSystem(turns, hint);
  }

  List<ChatTurn> _appendSystem(List<ChatTurn> turns, String hint) {
    final hasSystem = turns.any((ChatTurn t) => t.role == 'system');
    if (!hasSystem) {
      return <ChatTurn>[
        ChatTurn(role: 'system', content: hint.trim()),
        ...turns,
      ];
    }
    return <ChatTurn>[
      for (final ChatTurn t in turns)
        if (t.role == 'system')
          ChatTurn(
            role: t.role,
            content: t.content + hint,
            attachments: t.attachments,
          )
        else
          t,
    ];
  }

  List<ChatTurn> _withWebHint(List<ChatTurn> turns) {
    const hint =
        '\n\nWEB: to search output "SEARCH: <query>", to read a page '
        '"OPEN: <url>" — then stop and wait. Max 3 tool calls per '
        'answer, then answer in the user\'s language.';
    final hasSystem = turns.any((ChatTurn t) => t.role == 'system');
    if (!hasSystem) {
      return <ChatTurn>[
        ChatTurn(role: 'system', content: hint.trim()),
        ...turns,
      ];
    }
    return <ChatTurn>[
      for (final ChatTurn t in turns)
        if (t.role == 'system')
          ChatTurn(
            role: t.role,
            content: t.content + hint,
            attachments: t.attachments,
          )
        else
          t,
    ];
  }

  Future<String> _streamAttempt({
    required _Session session,
    required List<ChatTurn> turns,
    required int assistantId,
    required int attempt,
    String seedContent = '',
    String seedReasoning = '',
  }) async {
    final repo = ref.read(messageRepositoryProvider);
    state = ChatSessionState(
      isStreaming: true,
      streamingChatId: session.chat.id,
      streamingMessageId: assistantId,
      streamText: seedContent,
      streamReasoning: seedReasoning,
    );

    final params = ChatParams(
      apiKey: session.apiKey,
      baseUrl: session.baseUrl,
      model: session.model,
      turns: turns,
      reasoningEffort: (session.settings.reasoningEffort.isEmpty ||
              session.settings.reasoningEffort == 'auto')
          ? null
          : session.settings.reasoningEffort,
      maxTokens: session.settings.maxTokens,
      promptCaching: session.settings.promptCaching,
      timeout: Duration(seconds: session.settings.timeoutSeconds),
    );

    final token = CancelToken();
    _token = token;
    final contentBuffer = StringBuffer(seedContent);
    final reasoningBuffer = StringBuffer(seedReasoning);
    final splitter = ThinkSplitter();
    var handedOff = false;
    final startedAt = DateTime.now();
    var lastPush = startedAt;

    Future<void> persist() async {
      await repo.setContent(assistantId, contentBuffer.toString());
      if (reasoningBuffer.isNotEmpty) {
        await repo.setReasoning(assistantId, reasoningBuffer.toString());
      }
    }

    Future<void> finish() async {
      await persist();
      state = const ChatSessionState();
    }

    Future<void> recordFailure(ApiError error) async {
      await persist();
      await repo.setError(
        assistantId,
        errorType: error.type.name,
        errorDetails: error.details,
      );
      ref.read(debugLogProvider.notifier).add(error);
      state = ChatSessionState(lastError: error);
    }

    Future<String> recover(ApiError error) async {
      final interrupted =
          error.type == ApiErrorType.networkError ||
          error.type == ApiErrorType.timeout;
      final hasPartial =
          contentBuffer.isNotEmpty || reasoningBuffer.isNotEmpty;
      if (interrupted && attempt < 1 && !hasPartial) {
        await Future<void>.delayed(const Duration(seconds: 2));
        if (token.isCancelled) {
          await finish();
          return contentBuffer.toString();
        }
        handedOff = true;
        return await _streamAttempt(
          session: session,
          turns: turns,
          assistantId: assistantId,
          attempt: attempt + 1,
        );
      }
      if (interrupted && attempt < 1 && hasPartial) {
        await Future<void>.delayed(const Duration(seconds: 2));
        if (token.isCancelled) {
          await finish();
          return contentBuffer.toString();
        }
        handedOff = true;
        return await _streamAttempt(
          session: session,
          turns: <ChatTurn>[
            ...turns,
            ChatTurn(
              role: 'assistant',
              content: contentBuffer.toString(),
            ),
          ],
          assistantId: assistantId,
          attempt: attempt + 1,
          seedContent: contentBuffer.toString(),
          seedReasoning: reasoningBuffer.toString(),
        );
      }
      await recordFailure(error);
      return contentBuffer.toString();
    }

    try {
      await for (final delta
          in session.adapter.streamChat(params, cancelToken: token)) {
        if (delta.reasoning.isNotEmpty) {
          reasoningBuffer.write(delta.reasoning);
        }
        if (delta.text.isNotEmpty) {
          final split = splitter.feed(delta.text);
          reasoningBuffer.write(split.reasoning);
          contentBuffer.write(split.content);
        }
        final now = DateTime.now();
        if (now.difference(lastPush) >= const Duration(milliseconds: 120)) {
          lastPush = now;
          state = ChatSessionState(
            isStreaming: true,
            streamingChatId: session.chat.id,
            streamingMessageId: assistantId,
            streamText: contentBuffer.toString(),
            streamReasoning: reasoningBuffer.toString(),
          );
        }
      }
      final tail = splitter.close();
      reasoningBuffer.write(tail.reasoning);
      contentBuffer.write(tail.content);
      await _saveMetrics(
        session: session,
        turns: turns,
        assistantId: assistantId,
        reply: contentBuffer.toString(),
        reasoning: reasoningBuffer.toString(),
        durationMs: DateTime.now().difference(startedAt).inMilliseconds,
      );
      await finish();
      return contentBuffer.toString();
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        await finish();
        return contentBuffer.toString();
      } else {
        return await recover(ApiError.fromDio(e, session.adapter.format));
      }
    } on ApiError catch (error) {
      return await recover(error);
    } catch (e) {
      await recordFailure(
        ApiError(type: ApiErrorType.unknown, raw: '$e', cause: e),
      );
      return contentBuffer.toString();
    } finally {
      _token = null;
      if (!handedOff) {
        await _recordUsage(session, turns, contentBuffer.toString());
      }
    }
  }

  /// Stores per-reply token counts and speed on the assistant message.
  /// Provider-reported usage wins; otherwise the local heuristic is used and
  /// flagged as estimated so the UI can mark it.
  Future<void> _saveMetrics({
    required _Session session,
    required List<ChatTurn> turns,
    required int assistantId,
    required String reply,
    required String reasoning,
    required int durationMs,
  }) async {
    try {
      final usage = session.adapter.lastUsage;
      final sentTexts = <String>[for (final turn in turns) turn.content];
      final tokensIn = usage?.inputTokens ??
          estimateConversationTokens(sentTexts);
      final tokensOut = usage?.outputTokens ??
          estimateTokens(reply) + estimateTokens(reasoning);
      await ref.read(messageRepositoryProvider).setMetrics(
            assistantId,
            tokensIn: tokensIn,
            tokensOut: tokensOut,
            durationMs: durationMs,
            estimated: usage?.inputTokens == null ||
                usage?.outputTokens == null,
          );
    } catch (_) {
      // Metrics are decorative; never break a reply because of them.
    }
  }

  Future<void> _recordUsage(
    _Session session,
    List<ChatTurn> sent,
    String reply,
  ) async {
    try {
      final chatRepo = ref.read(chatRepositoryProvider);
      final chat = await chatRepo.getChat(session.chat.id);
      if (chat == null) return;
      final usage = session.adapter.lastUsage;
      final input = usage?.inputTokens ??
          estimateConversationTokens(
            <String>[for (final turn in sent) turn.content],
          );
      final output = usage?.outputTokens ??
          estimateConversationTokens(<String>[reply]);
      final thinking = usage?.thinkingTokens ?? 0;
      await chatRepo.setUsage(
        session.chat.id,
        input: chat.usageInput + input,
        output: chat.usageOutput + output,
        thinking: chat.usageThinking + thinking,
      );
    } catch (_) {
      // Usage accounting must never break a conversation.
    }
  }


  void _setUnknownFailure(Object cause) {
    final error = ApiError(
      type: ApiErrorType.unknown,
      raw: '$cause',
      cause: cause,
    );
    ref.read(debugLogProvider.notifier).add(error);
    state = ChatSessionState(lastError: error);
  }
}
