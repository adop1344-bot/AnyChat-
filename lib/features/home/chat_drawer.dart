import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_providers.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/ui/atoms.dart';
import '../../l10n/app_localizations.dart';
import '../settings/presentation/settings_screen.dart';
import '../chat/domain/models.dart';
import '../chat/state/chat_providers.dart';
import '../chat/state/chat_session.dart';
import '../chat/state/current_chat.dart';

class ChatDrawer extends ConsumerWidget {
  const ChatDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final chatsAsync = ref.watch(chatListProvider);
    final currentId = ref.watch(currentChatProvider).when(
          data: (int? value) => value,
          loading: () => null,
          error: (Object error, StackTrace stack) => null,
        );

    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            SizedBox(
              height: 56,
              child: Padding(
                padding: const EdgeInsets.only(
                  left: AppSpace.x4,
                  right: AppSpace.x2,
                ),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        l10n.appTitle,
                        style: theme.textTheme.titleLarge,
                      ),
                    ),
                    QuietIconButton(
                      icon: Icons.edit_outlined,
                      tooltip: l10n.newChat,
                      onPressed: () => _startNewChat(context, ref, l10n),
                    ),
                  ],
                ),
              ),
            ),
            const Hairline(),
            Expanded(
              child: chatsAsync.when(
                loading: () => const Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
                error: (Object error, StackTrace stack) =>
                    Center(child: Text(l10n.errUnknown('$error'))),
                data: (List<Chat> chats) {
                  if (chats.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpace.x6),
                        child: Text(
                          l10n.chatsEmpty,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      SectionLabel(
                        l10n.recentChats,
                        trailing: Figure(
                          '${chats.length}',
                          size: 10.5,
                          color: theme.colorScheme.onSurfaceVariant
                              .withValues(alpha: 0.7),
                        ),
                      ),
                      Expanded(
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpace.x2,
                          ),
                          itemCount: chats.length,
                          itemBuilder: (BuildContext ctx, int index) {
                            final chat = chats[index];
                            return _ChatRow(
                              chat: chat,
                              selected: chat.id == currentId,
                              onTap: () => _openChat(context, ref, chat.id),
                              onAction: (String value) {
                                switch (value) {
                                  case 'rename':
                                    _renameChat(context, ref, l10n, chat);
                                  case 'summarize':
                                    _summarizeChat(context, ref, l10n, chat);
                                  case 'prompt':
                                    _chatSystemPrompt(context, ref, chat);
                                  case 'delete':
                                    _deleteChat(
                                      context,
                                      ref,
                                      l10n,
                                      chat,
                                      currentId,
                                    );
                                }
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            const Hairline(),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.x3,
                AppSpace.x3,
                AppSpace.x2,
                AppSpace.x3,
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: FilledButton(
                      onPressed: () => _startNewChat(context, ref, l10n),
                      child: Text(l10n.newChat),
                    ),
                  ),
                  const SizedBox(width: AppSpace.x2),
                  QuietIconButton(
                    icon: Icons.settings_outlined,
                    tooltip: l10n.settingsTitle,
                    box: 40,
                    onPressed: () {
                      final navigator = Navigator.of(context);
                      navigator.pop();
                      navigator.push(
                        MaterialPageRoute<void>(
                          builder: (BuildContext routeContext) =>
                              const SettingsScreen(),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openChat(BuildContext context, WidgetRef ref, int chatId) {
    Navigator.of(context).pop();
    ref.read(currentChatProvider.notifier).open(chatId);
  }

  Future<void> _startNewChat(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) async {
    Navigator.of(context).pop();
    await ref.read(currentChatProvider.notifier).startNewChat(l10n.newChat);
  }

  Future<void> _renameChat(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
    Chat chat,
  ) async {
    final controller = TextEditingController(text: chat.title);
    String? result;
    try {
      result = await showDialog<String>(
        context: context,
        builder: (BuildContext dialogContext) {
          final dialogL10n = AppLocalizations.of(dialogContext);
          return AlertDialog(
            title: Text(dialogL10n.renameChat),
            content: TextField(
              controller: controller,
              autofocus: true,
              decoration: InputDecoration(
                labelText: dialogL10n.chatNameLabel,
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text(dialogL10n.cancel),
              ),
              FilledButton(
                onPressed: () =>
                    Navigator.of(dialogContext).pop(controller.text),
                child: Text(dialogL10n.save),
              ),
            ],
          );
        },
      );
    } finally {
      controller.dispose();
    }
    final title = result?.trim();
    if (title == null || title.isEmpty || !context.mounted) return;
    await ref.read(chatRepositoryProvider).renameChat(chat.id, title);
  }

  Future<void> _summarizeChat(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
    Chat chat,
  ) async {
    final newChatId = await ref
        .read(chatSessionProvider.notifier)
        .summarize(chat.id, prompt: l10n.handoffPrompt);
    if (!context.mounted || newChatId == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.handoffDone)),
    );
    ref.read(currentChatProvider.notifier).open(newChatId);
    if (context.mounted) Navigator.of(context).pop();
  }

  Future<void> _chatSystemPrompt(
    BuildContext context,
    WidgetRef ref,
    Chat chat,
  ) async {
    final controller = TextEditingController(text: chat.systemPrompt ?? '');
    String? result;
    try {
      result = await showDialog<String>(
        context: context,
        builder: (BuildContext dialogContext) {
          final l10n = AppLocalizations.of(dialogContext);
          return AlertDialog(
            title: Text(l10n.chatSystemPromptLabel),
            content: TextField(
              controller: controller,
              autofocus: true,
              minLines: 3,
              maxLines: 8,
              decoration: InputDecoration(hintText: l10n.systemPromptHint),
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
    if (result == null || !context.mounted) return;
    await ref.read(chatRepositoryProvider).setSystemPrompt(chat.id, result);
  }

  Future<void> _deleteChat(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
    Chat chat,
    int? currentId,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        final dialogL10n = AppLocalizations.of(dialogContext);
        return AlertDialog(
          title: Text(dialogL10n.deleteChat),
          content: Text(chat.title),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(dialogL10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(dialogContext).colorScheme.error,
                foregroundColor: Theme.of(dialogContext).colorScheme.onError,
              ),
              child: Text(dialogL10n.delete),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !context.mounted) return;
    await ref.read(chatRepositoryProvider).deleteChat(chat.id);
    if (!context.mounted) return;
    if (chat.id == currentId) {
      ref.read(currentChatProvider.notifier).closeChat();
    }
  }
}

class _ChatRow extends StatelessWidget {
  const _ChatRow({
    required this.chat,
    required this.selected,
    required this.onTap,
    required this.onAction,
  });

  final Chat chat;
  final bool selected;
  final VoidCallback onTap;
  final ValueChanged<String> onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: selected ? scheme.surfaceContainerHigh : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            height: 38,
            child: Row(
              children: <Widget>[
                const SizedBox(width: AppSpace.x2 + 2),
                SizedBox(
                  width: 6,
                  child: selected
                      ? Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            width: 2,
                            height: 16,
                            decoration: BoxDecoration(
                              color: scheme.primary,
                              borderRadius: BorderRadius.circular(1),
                            ),
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: AppSpace.x2),
                Expanded(
                  child: Text(
                    chat.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontSize: 14,
                      color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                PopupMenuButton<String>(
                  onSelected: onAction,
                  tooltip: '',
                  splashRadius: 16,
                  icon: Icon(
                    Icons.more_vert,
                    size: 16,
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                  ),
                  itemBuilder: (BuildContext menuContext) =>
                      <PopupMenuEntry<String>>[
                    PopupMenuItem<String>(
                      value: 'rename',
                      child: Text(AppLocalizations.of(menuContext).renameChat),
                    ),
                    PopupMenuItem<String>(
                      value: 'summarize',
                      child: Text(AppLocalizations.of(menuContext).handoff),
                    ),
                    PopupMenuItem<String>(
                      value: 'prompt',
                      child: Text(
                        AppLocalizations.of(menuContext).systemPromptLabel,
                      ),
                    ),
                    PopupMenuItem<String>(
                      value: 'delete',
                      child: Text(AppLocalizations.of(menuContext).deleteChat),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
