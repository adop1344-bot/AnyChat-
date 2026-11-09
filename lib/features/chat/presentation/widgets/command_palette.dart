import 'package:flutter/material.dart';

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

class CommandPalette extends StatelessWidget {
  const CommandPalette({super.key, required this.onPick});

  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 0, 8, 4),
      constraints: const BoxConstraints(maxHeight: 220),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ListView.builder(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: kChatCommands.length,
        itemBuilder: (BuildContext context, int index) {
          final cmd = kChatCommands[index];
          return ListTile(
            dense: true,
            leading: Icon(
              switch (cmd.name) {
                '/widget' => Icons.widgets_outlined,
                '/search' => Icons.search,
                '/end' => Icons.all_inclusive,
                '/stop' => Icons.stop,
                _ => Icons.help_outline,
              },
              size: 20,
              color: scheme.primary,
            ),
            title: Text(
              cmd.name,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              cmd.description,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () => onPick(cmd.name),
          );
        },
      ),
    );
  }
}
