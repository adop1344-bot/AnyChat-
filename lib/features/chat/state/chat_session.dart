import 'package:dio/dio.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../app_providers.dart';
import '../../../core/errors/api_error.dart';
import '../../../core/network/think_splitter.dart';
import '../../../core/storage/token_estimator.dart';
import '../../../core/errors/debug_log.dart';
import '../../../features/providers/data/provider_adapter.dart';
import '../../settings/app_settings.dart';
import '../../settings/state/settings_controller.dart';
import '../data/message_repository.dart';
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
  });

  final bool isStreaming;
  final int? streamingChatId;
  final int? streamingMessageId;
  final String streamText;
  final String streamReasoning;
  final bool busy;
  final ApiError? lastError;
  final ChatIssue? lastIssue;

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
    await _generate(session: session, turns: _historyTurns(session, fresh));
  }

  void stop() {
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
  }) async {
    if (turns.isEmpty) return;
    final repo = ref.read(messageRepositoryProvider);
    final assistantId = await repo.insertMessage(
      chatId: session.chat.id,
      branchId: session.branchId,
      role: 'assistant',
      content: '',
      model: session.model,
    );
    await _streamAttempt(
      session: session,
      turns: turns,
      assistantId: assistantId,
      attempt: 0,
    );
  }

  Future<void> _streamAttempt({
    required _Session session,
    required List<ChatTurn> turns,
    required int assistantId,
    required int attempt,
  }) async {
    final repo = ref.read(messageRepositoryProvider);
    state = ChatSessionState(
      isStreaming: true,
      streamingChatId: session.chat.id,
      streamingMessageId: assistantId,
    );

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

    final token = CancelToken();
    _token = token;
    final contentBuffer = StringBuffer();
    final reasoningBuffer = StringBuffer();
    final splitter = ThinkSplitter();
    var handedOff = false;
    var lastPush = DateTime.now();

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

    Future<void> recover(ApiError error) async {
      final interrupted =
          error.type == ApiErrorType.networkError ||
          error.type == ApiErrorType.timeout;
      if (interrupted &&
          attempt < 1 &&
          contentBuffer.isEmpty &&
          reasoningBuffer.isEmpty) {
        await Future<void>.delayed(const Duration(seconds: 2));
        if (token.isCancelled) {
          await finish();
          return;
        }
        handedOff = true;
        await _streamAttempt(
          session: session,
          turns: turns,
          assistantId: assistantId,
          attempt: attempt + 1,
        );
        return;
      }
      await recordFailure(error);
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
      await finish();
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        await finish();
      } else {
        await recover(ApiError.fromDio(e, session.adapter.format));
      }
    } on ApiError catch (error) {
      await recover(error);
    } catch (e) {
      await recordFailure(
        ApiError(type: ApiErrorType.unknown, raw: '$e', cause: e),
      );
    } finally {
      _token = null;
      if (!handedOff) {
        await _recordUsage(session, turns, contentBuffer.toString());
      }
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
