import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_providers.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/theme/style_tokens.dart';
import '../../core/ui/atoms.dart';
import '../../core/ui/glass.dart';
import '../../core/ui/motion.dart';
import '../../l10n/app_localizations.dart';
import '../settings/presentation/settings_screen.dart';
import '../chat/domain/models.dart';
import '../chat/state/chat_providers.dart';
import '../chat/state/chat_session.dart';
import '../chat/state/current_chat.dart';
import 'pinned_chats.dart';

class ChatDrawer extends ConsumerStatefulWidget {
  const ChatDrawer({super.key});

  @override
  ConsumerState<ChatDrawer> createState() => _ChatDrawerState();
}

class _ChatDrawerState extends ConsumerState<ChatDrawer> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final chatsAsync = ref.watch(chatListProvider);
    final List<int> pinned = ref.watch(pinnedChatsProvider).value ?? const <int>[];
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
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.x3,
                AppSpace.x2,
                AppSpace.x3,
                AppSpace.x1,
              ),
              child: TextField(
                controller: _searchController,
                onChanged: (String value) =>
                    setState(() => _query = value.trim().toLowerCase()),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: l10n.searchChats,
                  hintStyle: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  prefixIcon: Icon(
                    Icons.search,
                    size: 16,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  prefixIconConstraints: const BoxConstraints(
                    minWidth: 34,
                    minHeight: 34,
                  ),
                  fillColor: theme.colorScheme.surfaceContainerLow,
                  contentPadding: const EdgeInsets.symmetric(
                    vertical: AppSpace.x2,
                    horizontal: AppSpace.x2,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.control),
                    borderSide:
                        BorderSide(color: theme.colorScheme.outlineVariant),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.control),
                    borderSide:
                        BorderSide(color: theme.colorScheme.outlineVariant),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.control),
                    borderSide: BorderSide(color: theme.colorScheme.primary),
                  ),
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
                data: (List<Chat> allChats) {
                  final List<Chat> filtered = _query.isEmpty
                      ? allChats
                      : allChats
                          .where((Chat c) =>
                              c.title.toLowerCase().contains(_query))
                          .toList();
                  // Pinned first, everything else in its natural order.
                  final List<Chat> chats = <Chat>[
                    ...filtered.where((Chat c) => pinned.contains(c.id)),
                    ...filtered.where((Chat c) => !pinned.contains(c.id)),
                  ];
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
                            return Appear(
                              delay: Duration(
                                milliseconds: (index * 18).clamp(0, 180).toInt(),
                              ),
                              rise: 6,
                              child: _ChatRow(
                              chat: chat,
                              selected: chat.id == currentId,
                              pinned: pinned.contains(chat.id),
                              onTap: () => _openChat(context, ref, chat.id),
                              onAction: (String value) {
                                switch (value) {
                                  case 'rename':
                                    _renameChat(context, ref, l10n, chat);
                                  case 'summarize':
                                    _summarizeChat(context, ref, l10n, chat);
                                  case 'prompt':
                                    _chatSystemPrompt(context, ref, chat);
                                  case 'export':
                                    _exportChat(context, ref, chat);
                                  case 'pin':
                                    ref
                                        .read(pinnedChatsProvider.notifier)
                                        .toggle(chat.id);
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
                              ),
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

  /// Saves the whole conversation as Markdown, ready to paste anywhere.
  Future<void> _exportChat(
    BuildContext context,
    WidgetRef ref,
    Chat chat,
  ) async {
    final List<Message> messages =
        await ref.read(messageRepositoryProvider).listMessages(chat.id);
    final StringBuffer out = StringBuffer()
      ..writeln('# ${chat.title}')
      ..writeln()
      ..writeln('_${chat.createdAt.toIso8601String().split('T').first}_')
      ..writeln();
    for (final Message message in messages) {
      final String who = message.role == 'user' ? 'You' : message.model ?? 'Assistant';
      out.writeln('## $who');
      out.writeln();
      out.writeln(message.content.trim());
      out.writeln();
    }
    final String name = chat.title
        .replaceAll(RegExp(r'[^\wа-яА-ЯёЁ -]'), '')
        .trim()
        .replaceAll(' ', '-');
    final Uri? uri = await FilePicker.saveFile(
      fileName: '${name.isEmpty ? 'chat' : name}.md',
      bytes: Uint8List.fromList(utf8.encode(out.toString())),
    );
    if (!context.mounted || uri == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context).exportDone)),
    );
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
    required this.pinned,
    required this.onTap,
    required this.onAction,
  });

  final Chat chat;
  final bool selected;
  final bool pinned;
  final VoidCallback onTap;
  final ValueChanged<String> onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final StyleTokens tokens = StyleTokens.of(context);
    final double radius = tokens.instrument ? 8 : tokens.controlRadius;
    return Padding(
      padding: EdgeInsets.only(bottom: tokens.instrument ? 2 : 2),
      child: Material(
        color: selected
            ? (tokens.glass
                ? Colors.white.withValues(
                    alpha: theme.brightness == Brightness.dark ? 0.18 : 0.62,
                  )
                : tokens.instrument
                    ? scheme.surfaceContainerHigh
                    : scheme.secondaryContainer)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(radius),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(radius),
          child: SizedBox(
            height: tokens.rowHeight,
            child: Row(
              children: <Widget>[
                const SizedBox(width: AppSpace.x2 + 2),
                SizedBox(
                  width: tokens.instrument ? 6 : 0,
                  child: selected && tokens.instrument
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
                if (pinned) ...<Widget>[
                  Icon(
                    Icons.push_pin,
                    size: 12,
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                  ),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: Text(
                    chat.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontSize: tokens.instrument ? 14 : 15,
                      color: selected
                          ? (tokens.instrument
                              ? scheme.onSurface
                              : scheme.onSecondaryContainer)
                          : scheme.onSurfaceVariant,
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
                      value: 'pin',
                      child: Text(
                        pinned
                            ? AppLocalizations.of(menuContext).unpinChat
                            : AppLocalizations.of(menuContext).pinChat,
                      ),
                    ),
                    PopupMenuItem<String>(
                      value: 'export',
                      child: Text(AppLocalizations.of(menuContext).exportChat),
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
