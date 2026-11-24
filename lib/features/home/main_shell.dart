import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_tokens.dart';
import '../../l10n/app_localizations.dart';
import '../chat/presentation/chat_screen.dart';
import '../chat/presentation/widgets/chat_composer.dart';
import '../chat/presentation/widgets/menu_glyph.dart';
import '../chat/state/chat_session.dart';
import '../chat/state/current_chat.dart';
import '../chat/domain/models.dart';
import 'chat_drawer.dart';

class MainShell extends ConsumerWidget {
  const MainShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final current = ref.watch(currentChatProvider);
    return current.when<Widget>(
      loading: () => const Scaffold(
        body: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ),
      error: (Object error, StackTrace stack) => Scaffold(
        body: Center(child: Text(l10n.errUnknown('$error'))),
      ),
      data: (int? chatId) {
        if (chatId == null) {
          return _EmptyHome(l10n: l10n);
        }
        return ChatScreen(key: ValueKey<int>(chatId), chatId: chatId);
      },
    );
  }
}

class _EmptyHome extends ConsumerWidget {
  const _EmptyHome({required this.l10n});

  final AppLocalizations l10n;

  Future<void> _send(
    BuildContext context,
    WidgetRef ref,
    String text,
    List<ChatAttachment> attachments,
  ) async {
    final shell = ref.read(currentChatProvider.notifier);
    await shell.startNewChat(l10n.newChat);
    final current = ref.read(currentChatProvider);
    final newChatId = current.when<int?>(
      data: (int? value) => value,
      loading: () => null,
      error: (Object error, StackTrace stack) => null,
    );
    if (newChatId == null) return;
    await ref.read(chatSessionProvider.notifier).send(
          newChatId,
          text,
          attachments: attachments,
        );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      drawer: const ChatDrawer(),
      body: Builder(
        builder: (BuildContext scaffoldContext) => SafeArea(
          bottom: false,
          child: Column(
            children: <Widget>[
              Container(
                height: 56,
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.x2),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: theme.colorScheme.outlineVariant,
                    ),
                  ),
                ),
                child: Row(
                  children: <Widget>[
                    IconButton(
                      tooltip: l10n.menu,
                      onPressed: () =>
                          Scaffold.of(scaffoldContext).openDrawer(),
                      icon: const MenuGlyph(size: 18),
                    ),
                    const SizedBox(width: AppSpace.x1),
                    Text(l10n.appTitle, style: theme.textTheme.titleMedium),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpace.x4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
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
                      for (final String suggestion in <String>[
                        l10n.suggest1,
                        l10n.suggest2,
                        l10n.suggest3,
                      ])
                        InkWell(
                          onTap: () => _send(context, ref, suggestion, const <ChatAttachment>[]),
                          borderRadius:
                              BorderRadius.circular(AppRadius.control),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: AppSpace.x3,
                            ),
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
              ),
              ChatComposer(
                isBusy: false,
                onStop: () {},
                onSend: (String text, List<ChatAttachment> attachments) =>
                    _send(context, ref, text, attachments),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
