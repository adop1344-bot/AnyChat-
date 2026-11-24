import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/error_localizer.dart';
import '../../../core/storage/token_estimator.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/ui/atoms.dart';
import '../../../l10n/app_localizations.dart';
import '../../home/chat_drawer.dart';
import '../../settings/app_settings.dart';
import '../../settings/state/settings_controller.dart';
import '../domain/models.dart';
import '../state/chat_providers.dart';
import '../state/chat_session.dart';
import '../state/current_chat.dart';
import 'widgets/chat_composer.dart';
import 'widgets/command_palette.dart';
import 'widgets/context_circle.dart';
import 'widgets/menu_glyph.dart';
import 'widgets/message_bubble.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.chatId});

  final int chatId;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final ScrollController _scroll = ScrollController();
  final TextEditingController _inputController = TextEditingController();
  bool _showJump = false;
  String? _palettePrefix;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.dispose();
    _inputController.dispose();
    super.dispose();
  }

  void _onScroll() {
    final show = _scroll.hasClients && _scroll.offset > 600;
    if (show != _showJump) {
      setState(() => _showJump = show);
    }
  }

  void _onInputChanged(String text) {
    final t = text.trimLeft();
    final show = t.startsWith('/') &&
        !t.contains(' ') &&
        kChatCommands.any((ChatCommand c) => c.name.startsWith(t));
    final next = show ? t : null;
    if (next != _palettePrefix) {
      setState(() => _palettePrefix = next);
    }
  }

  Future<void> _editMessage(Message message) async {
    final controller = TextEditingController(text: message.content);
    String? result;
    try {
      result = await showDialog<String>(
        context: context,
        builder: (BuildContext dialogContext) {
          final l10n = AppLocalizations.of(dialogContext);
          return AlertDialog(
            title: Text(l10n.editMessageTitle),
            content: TextField(
              controller: controller,
              autofocus: true,
              minLines: 3,
              maxLines: 8,
              decoration: InputDecoration(hintText: l10n.editMessageHint),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text(l10n.cancel),
              ),
              FilledButton(
                onPressed: () =>
                    Navigator.of(dialogContext).pop(controller.text),
                child: Text(l10n.save),
              ),
            ],
          );
        },
      );
    } finally {
      controller.dispose();
    }
    final edited = result?.trim();
    if (edited == null || edited.isEmpty || !mounted) return;
    if (edited == message.content) return;
    await ref
        .read(chatSessionProvider.notifier)
        .editMessage(widget.chatId, message.id, edited);
  }

  Future<void> _branchFrom(Message message) async {
    await ref
        .read(chatSessionProvider.notifier)
        .branchFrom(widget.chatId, message.id);
  }

  Future<void> _startNewChat() async {
    final l10n = AppLocalizations.of(context);
    await ref.read(currentChatProvider.notifier).startNewChat(l10n.newChat);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final chatAsync = ref.watch(chatByIdProvider(widget.chatId));
    final messagesAsync = ref.watch(chatMessagesProvider(widget.chatId));
    final branchesAsync = ref.watch(chatBranchesProvider(widget.chatId));
    final session = ref.watch(chatSessionProvider);

    ref.listen<ChatSessionState>(
      chatSessionProvider,
      (ChatSessionState? previous, ChatSessionState next) {
        if (!next.hasFailure) return;
        final sameError = previous != null &&
            identical(previous.lastError, next.lastError) &&
            identical(previous.lastIssue, next.lastIssue);
        if (sameError) return;
        final issue = next.lastIssue;
        final error = next.lastError;
        final String message;
        if (issue != null) {
          message = _issueMessage(l10n, issue);
        } else if (error != null) {
          message = localizeApiError(l10n, error);
        } else {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      },
    );

    final branches = branchesAsync.when(
      data: (List<Branch> value) => value,
      loading: () => <Branch>[],
      error: (Object error, StackTrace stack) => <Branch>[],
    );

    return chatAsync.when<Widget>(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (Object error, StackTrace stack) => Scaffold(
        body: Center(child: Text(l10n.errUnknown('$error'))),
      ),
      data: (Chat? chat) {
        if (chat == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              ref.read(currentChatProvider.notifier).closeChat();
            }
          });
          return const Scaffold(body: SizedBox.shrink());
        }
        return Scaffold(
          drawer: const ChatDrawer(),
          body: Builder(
            builder: (BuildContext scaffoldContext) => SafeArea(
              bottom: false,
              child: Column(
                children: <Widget>[
                  _ChatTopBar(
                    title: chat.title,
                    onMenu: () => Scaffold.of(scaffoldContext).openDrawer(),
                    onNewChat: _startNewChat,
                  ),
                  if (session.busy)
                    const LinearProgressIndicator(minHeight: 2),
                  Expanded(
                    child: messagesAsync.when(
                      loading: () => const Center(
                        child: CircularProgressIndicator(),
                      ),
                      error: (Object error, StackTrace stack) => Center(
                        child: Text(l10n.errUnknown('$error')),
                      ),
                      data: (List<Message> allMessages) => _buildChatBody(
                        l10n,
                        chat,
                        allMessages,
                        branches,
                        session,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildChatBody(
    AppLocalizations l10n,
    Chat chat,
    List<Message> allMessages,
    List<Branch> branches,
    ChatSessionState session,
  ) {
    final branchId = chat.activeBranchId;
    final messages = branchId == null
        ? <Message>[]
        : allMessages
            .where((Message message) => message.branchId == branchId)
            .toList();

    final settings = ref.watch(settingsControllerProvider).when(
          data: (AppSettings value) => value,
          loading: () => const AppSettings(),
          error: (Object error, StackTrace stack) => const AppSettings(),
        );
    final chatPrompt = chat.systemPrompt;
    final systemPrompt = (chatPrompt != null && chatPrompt.trim().isNotEmpty)
        ? chatPrompt
        : settings.systemPrompt;

    final usage = computeContextUsage(settings, messages, systemPrompt);

    // The anchor is the message that actually differs between this branch and
    // a sibling (falling back to the last answer): the ‹1/2› pager and its
    // actions live there, so they never jump to newer messages.
    Message? anchor;
    if (branches.length > 1) {
      search:
      for (final sibling in branches) {
        if (sibling.id == branchId) continue;
        final other =
            allMessages.where((Message m) => m.branchId == sibling.id).toList();
        final n =
            messages.length < other.length ? messages.length : other.length;
        for (var i = 0; i < n; i++) {
          if (messages[i].role != other[i].role ||
              messages[i].content != other[i].content) {
            anchor = messages[i];
            break search;
          }
        }
      }
      if (anchor == null) {
        for (var i = messages.length - 1; i >= 0; i--) {
          if (messages[i].role == 'assistant') {
            anchor = messages[i];
            break;
          }
        }
      } else if (anchor.role != 'assistant') {
        final start = messages.indexOf(anchor);
        for (var i = start; i < messages.length; i++) {
          if (messages[i].role == 'assistant') {
            anchor = messages[i];
            break;
          }
        }
      }
    }
    final anchorId = anchor?.id;
    final reversed = messages.reversed.toList();

    return Column(
      children: <Widget>[
        _ContextStrip(
          used: usage.used,
          limit: usage.limit,
          approximate: usage.approximate,
          onTap: () => _showContextStats(
            l10n,
            chat,
            usage.used,
            usage.limit,
            usage.approximate,
          ),
        ),
        if (session.toolNotice.isNotEmpty) _ToolNotice(text: session.toolNotice),
        Expanded(
          child: Stack(
            children: <Widget>[
              messages.isEmpty
                  ? _EmptyChat(
                      l10n: l10n,
                      onPick: (String text) => ref
                          .read(chatSessionProvider.notifier)
                          .send(widget.chatId, text),
                    )
                  : ListView.builder(
                      controller: _scroll,
                      reverse: true,
                      padding: const EdgeInsets.only(top: 12, bottom: 12),
                      itemCount: reversed.length,
                      itemBuilder: (BuildContext itemContext, int index) {
                        final message = reversed[index];
                        final isLast = index == 0;
                        final isAssistant = message.role == 'assistant';
                        final isStreaming = session.isStreaming &&
                            session.streamingMessageId == message.id;
                        final isAnchor = message.id == anchorId;
                        final canRegenerate =
                            isAssistant && (isLast || isAnchor);
                        BranchPager? branchPager;
                        if (isAnchor &&
                            branches.length > 1 &&
                            !session.isStreaming &&
                            !session.busy) {
                          var index = branches.indexWhere(
                            (Branch b) => b.id == chat.activeBranchId,
                          );
                          if (index < 0) index = 0;
                          branchPager = (
                            current: index + 1,
                            total: branches.length,
                            onPrev: index > 0
                                ? () => _switchTo(branches[index - 1].id)
                                : null,
                            onNext: index < branches.length - 1
                                ? () => _switchTo(branches[index + 1].id)
                                : null,
                          );
                        }
                        return MessageBubble(
                          message: message,
                          streamingText: session.streamText,
                          streamingReasoning: session.streamReasoning,
                          toolSteps: isStreaming
                              ? session.streamToolSteps
                              : message.toolSteps,
                          isStreaming: isStreaming,
                          isLast: isLast,
                          showRegenerate: canRegenerate,
                          onEdit: message.role == 'user'
                              ? () => _editMessage(message)
                              : null,
                          onBranch: () => _branchFrom(message),
                          onRegenerate: canRegenerate
                              ? () => ref
                                  .read(chatSessionProvider.notifier)
                                  .regenerate(widget.chatId, message.id)
                              : null,
                          branchPager: branchPager,
                        );
                      },
                    ),
              if (_showJump)
                Positioned(
                  right: AppSpace.x4,
                  bottom: AppSpace.x4,
                  child: _JumpButton(
                    onTap: () => _scroll.animateTo(
                      0,
                      duration: AppMotion.base,
                      curve: AppMotion.curve,
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (_palettePrefix != null)
          CommandPalette(
            onPick: (String cmd) {
              _inputController.text = '$cmd ';
              _inputController.selection = TextSelection.fromPosition(
                TextPosition(offset: _inputController.text.length),
              );
              setState(() => _palettePrefix = null);
            },
          ),
        ChatComposer(
          controller: _inputController,
          onTextChanged: _onInputChanged,
          isBusy: session.isStreaming || session.busy,
          onStop: () => ref.read(chatSessionProvider.notifier).stop(),
          onSend: (String text, List<ChatAttachment> attachments) =>
              ref.read(chatSessionProvider.notifier).send(
                    widget.chatId,
                    text,
                    attachments: attachments,
                  ),
        ),
      ],
    );
  }

  void _showContextStats(
    AppLocalizations l10n,
    Chat chat,
    int used,
    int limit,
    bool approximate,
  ) {
    final free = limit > used ? limit - used : 0;
    final ratio = limit <= 0 ? 0.0 : used / limit;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheetContext) {
        final dl = AppLocalizations.of(sheetContext);
        final ThemeData theme = Theme.of(sheetContext);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpace.x5,
              0,
              AppSpace.x5,
              AppSpace.x5,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(dl.contextDetails, style: theme.textTheme.titleLarge),
                const SizedBox(height: AppSpace.x4),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Meter(ratio: ratio, height: 4),
                    ),
                    const SizedBox(width: AppSpace.x3),
                    Figure(
                      '${(ratio.clamp(0.0, 1.0) * 100).toStringAsFixed(0)}%',
                      size: 12,
                      weight: FontWeight.w500,
                      color: contextStatusColor(ratio),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpace.x4),
                _statRow(
                  dl.statUsed,
                  approximate
                      ? '~${formatTokenCount(used)}'
                      : formatTokenCount(used),
                ),
                _statRow(dl.statFree, formatTokenCount(free)),
                const SizedBox(height: AppSpace.x2),
                const Hairline(),
                const SizedBox(height: AppSpace.x2),
                _statRow(dl.statInput, formatTokenCount(chat.usageInput)),
                _statRow(dl.statOutput, formatTokenCount(chat.usageOutput)),
                _statRow(dl.statThinking, formatTokenCount(chat.usageThinking)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _statRow(String label, String value) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.x2),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Figure(value, size: 12.5, weight: FontWeight.w500),
        ],
      ),
    );
  }

  void _switchTo(int branchId) {
    ref
        .read(chatSessionProvider.notifier)
        .switchBranch(widget.chatId, branchId);
  }

  static String _issueMessage(AppLocalizations l10n, ChatIssue issue) {
    return switch (issue) {
      ChatIssue.noKey => l10n.keyMissing,
      ChatIssue.noModel => l10n.errNoModel,
      ChatIssue.noChat => l10n.errNoChat,
      ChatIssue.noProvider => l10n.errNoProvider,
    };
  }
}

/// Top bar: navigation, the chat's own name, and one action. The model lives
/// in the instrument strip below, next to the context meter it belongs with.
class _ChatTopBar extends StatelessWidget {
  const _ChatTopBar({
    required this.title,
    required this.onMenu,
    required this.onNewChat,
  });

  final String title;
  final VoidCallback onMenu;
  final VoidCallback onNewChat;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      height: 56,
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        children: <Widget>[
          const SizedBox(width: AppSpace.x2),
          IconButton(
            tooltip: AppLocalizations.of(context).menu,
            onPressed: onMenu,
            icon: const MenuGlyph(size: 18),
          ),
          const SizedBox(width: AppSpace.x1),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium,
            ),
          ),
          QuietIconButton(
            icon: Icons.add_comment_outlined,
            tooltip: AppLocalizations.of(context).newChat,
            onPressed: onNewChat,
          ),
          const SizedBox(width: AppSpace.x2),
        ],
      ),
    );
  }
}

/// The signature: a hairline instrument row under the top bar. Context meter
/// on the left, the active model on the right, both tappable.
class _ContextStrip extends ConsumerWidget {
  const _ContextStrip({
    required this.used,
    required this.limit,
    required this.approximate,
    required this.onTap,
  });

  final int used;
  final int limit;
  final bool approximate;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final double ratio = limit <= 0 ? 0 : used / limit;
    final Color status = contextStatusColor(ratio);
    final String mark = approximate ? '~' : '';
    final settings = ref.watch(settingsControllerProvider).when(
          data: (AppSettings value) => value,
          loading: () => const AppSettings(),
          error: (Object error, StackTrace stack) => const AppSettings(),
        );
    final modelLabel = settings.selectedModelId ?? '—';

    return Material(
      color: theme.colorScheme.surface,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.x4),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
          ),
          child: Row(
            children: <Widget>[
              Meter(ratio: ratio, width: 48, height: 3, color: status),
              const SizedBox(width: AppSpace.x2),
              Figure(
                '$mark${formatTokenCount(used)} / ${formatTokenCount(limit)}',
                size: 11,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const Spacer(),
              Flexible(
                child: Text(
                  modelLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: AppType.figure(
                    11,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToolNotice extends StatelessWidget {
  const _ToolNotice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpace.x4,
        vertical: AppSpace.x2,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        children: <Widget>[
          StatusDot(color: theme.colorScheme.primary),
          const SizedBox(width: AppSpace.x2),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppType.figure(
                11,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _JumpButton extends StatelessWidget {
  const _JumpButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(AppRadius.control),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.control),
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.control),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Icon(
            Icons.arrow_downward,
            size: 16,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// First screen of an empty chat: the question, then three quiet rows.
class _EmptyChat extends StatelessWidget {
  const _EmptyChat({required this.l10n, required this.onPick});

  final AppLocalizations l10n;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<String> suggestions = <String>[
      l10n.suggest1,
      l10n.suggest2,
      l10n.suggest3,
    ];
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpace.x4,
          AppSpace.x10,
          AppSpace.x4,
          AppSpace.x6,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(l10n.startWith, style: theme.textTheme.headlineMedium),
            const SizedBox(height: AppSpace.x2),
            Text(
              l10n.emptyChatHint,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpace.x6),
            for (final String suggestion in suggestions)
              InkWell(
                onTap: () => onPick(suggestion),
                borderRadius: BorderRadius.circular(AppRadius.control),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpace.x3),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          suggestion,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                      Icon(
                        Icons.arrow_outward,
                        size: 15,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
