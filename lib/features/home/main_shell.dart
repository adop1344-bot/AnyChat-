import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../chat/presentation/chat_screen.dart';
import '../chat/presentation/widgets/menu_glyph.dart';
import '../chat/presentation/widgets/chat_composer.dart';
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
        body: Center(child: CircularProgressIndicator()),
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
    final theme = Theme.of(context);
    return Scaffold(
      drawer: const ChatDrawer(),
      body: Builder(
        builder: (BuildContext scaffoldContext) => SafeArea(
          child: Stack(
            children: <Widget>[
              Column(
                children: <Widget>[
                  const SizedBox(height: 56),
                  Expanded(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Text(
                          l10n.startWith,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
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
              Positioned(
                top: 4,
                left: 4,
                child: Builder(
                  builder: (BuildContext buttonContext) => IconButton(
                    tooltip: l10n.menu,
                    icon: const MenuGlyph(),
                    onPressed: () =>
                        Scaffold.of(buttonContext).openDrawer(),
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
