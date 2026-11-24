import 'package:flutter/material.dart';

import '../../../../core/theme/app_tokens.dart';

class ChatCommand {
  const ChatCommand(this.name, this.description);

  final String name;
  final String description;
}

const List<ChatCommand> kChatCommands = <ChatCommand>[
  ChatCommand('/widget', 'создать виджет в этом чате'),
  ChatCommand('/search', 'поиск в интернете для одного ответа'),
  ChatCommand('/end', 'автономно доделать задачу до конца'),
  ChatCommand('/stop', 'остановить генерацию'),
  ChatCommand('/help', 'список команд'),
];

/// Command palette: a hairline list above the composer, mono command names.
class CommandPalette extends StatelessWidget {
  const CommandPalette({super.key, required this.onPick});

  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppSpace.x3,
        0,
        AppSpace.x3,
        AppSpace.x1,
      ),
      constraints: const BoxConstraints(maxHeight: 220),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: ListView.builder(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: AppSpace.x1),
        itemCount: kChatCommands.length,
        itemBuilder: (BuildContext context, int index) {
          final ChatCommand cmd = kChatCommands[index];
          return InkWell(
            onTap: () => onPick(cmd.name),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpace.x3,
                vertical: AppSpace.x2,
              ),
              child: Row(
                children: <Widget>[
                  SizedBox(
                    width: 16,
                    child: Icon(
                      switch (cmd.name) {
                        '/widget' => Icons.widgets_outlined,
                        '/search' => Icons.search,
                        '/end' => Icons.all_inclusive,
                        '/stop' => Icons.stop,
                        _ => Icons.help_outline,
                      },
                      size: 13,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: AppSpace.x2),
                  SizedBox(
                    width: 68,
                    child: Text(
                      cmd.name,
                      style: AppType.figure(
                        12,
                        weight: FontWeight.w500,
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      cmd.description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
