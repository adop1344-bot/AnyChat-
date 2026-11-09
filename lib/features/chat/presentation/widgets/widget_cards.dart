import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app_providers.dart';
import '../../data/widget_repository.dart';

class ChatWidgetStrip extends ConsumerWidget {
  const ChatWidgetStrip({super.key, required this.chatId});

  final int chatId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final widgets = ref.watch(widgetListProvider(chatId));
    return widgets.when(
      loading: () => const SizedBox.shrink(),
      error: (Object e, StackTrace st) => const SizedBox.shrink(),
      data: (List<ChatWidget> list) {
        if (list.isEmpty) return const SizedBox.shrink();
        return SizedBox(
          height: 116,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
            itemCount: list.length,
            separatorBuilder: (BuildContext context, int index) =>
                const SizedBox(width: 8),
            itemBuilder: (BuildContext ctx, int i) =>
                _WidgetCard(widget: list[i]),
          ),
        );
      },
    );
  }
}

class _WidgetCard extends ConsumerWidget {
  const _WidgetCard({required this.widget});

  final ChatWidget widget;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 150,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(_iconFor(widget.type), size: 16, color: scheme.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  widget.title.isEmpty ? _nameFor(widget.type) : widget.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .labelLarge
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              InkWell(
                onTap: () => ref
                    .read(widgetRepositoryProvider)
                    .remove(widget.id),
                child: Icon(
                  Icons.close,
                  size: 14,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Expanded(child: _bodyFor(context, ref, scheme)),
        ],
      ),
    );
  }

  static IconData _iconFor(String type) => switch (type) {
        'counter' => Icons.tag,
        'note' => Icons.sticky_note_2_outlined,
        'todo' => Icons.checklist,
        _ => Icons.widgets_outlined,
      };

  static String _nameFor(String type) => switch (type) {
        'counter' => 'Счётчик',
        'note' => 'Заметка',
        'todo' => 'Чек-лист',
        _ => 'Виджет',
      };

  Widget _bodyFor(
    BuildContext context,
    WidgetRef ref,
    ColorScheme scheme,
  ) {
    switch (widget.type) {
      case 'counter':
        final value = widget.config['value'];
        final step = widget.config['step'];
        final unit = widget.config['unit'];
        final intValue = value is int ? value : int.tryParse('$value') ?? 0;
        final intStep = step is int ? step : int.tryParse('$step') ?? 1;
        final unitStr = unit is String ? unit : '';
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(
              '$intValue${unitStr.isEmpty ? '' : ' $unitStr'}',
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 2),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _bump(ref, -intStep),
                  icon: const Icon(Icons.remove_circle_outline),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _bump(ref, intStep),
                  icon: const Icon(Icons.add_circle_outline),
                ),
              ],
            ),
          ],
        );
      case 'note':
        final text = widget.config['text'];
        final textStr = text is String ? text : '';
        return SingleChildScrollView(
          child: Text(
            textStr,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        );
      case 'todo':
        final items = widget.config['items'];
        final list = items is List ? items : <dynamic>[];
        return ListView.builder(
          padding: EdgeInsets.zero,
          itemCount: list.length,
          itemBuilder: (BuildContext ctx, int i) {
            final item = list[i];
            final map = item is Map<String, dynamic> ? item : <String, dynamic>{};
            final done = map['done'] == true;
            final text = (map['text'] ?? '').toString();
            return InkWell(
              onTap: () => _toggleTodo(ref, i, !done),
              child: Row(
                children: <Widget>[
                  Icon(
                    done ? Icons.check_box : Icons.check_box_outline_blank,
                    size: 16,
                    color: done ? scheme.primary : scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        decoration: done ? TextDecoration.lineThrough : null,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      default:
        return const SizedBox.shrink();
    }
  }

  void _bump(WidgetRef ref, int delta) {
    final value = widget.config['value'];
    final intValue = value is int ? value : int.tryParse('$value') ?? 0;
    final next = <String, dynamic>{...widget.config, 'value': intValue + delta};
    ref.read(widgetRepositoryProvider).updateConfig(widget.id, next);
  }

  void _toggleTodo(WidgetRef ref, int index, bool done) {
    final items = widget.config['items'];
    final list = items is List
        ? <dynamic>[...items]
        : <dynamic>[];
    if (index >= list.length) return;
    final item = list[index];
    final map = item is Map<String, dynamic>
        ? <String, dynamic>{...item}
        : <String, dynamic>{};
    map['done'] = done;
    list[index] = map;
    final next = <String, dynamic>{...widget.config, 'items': list};
    ref.read(widgetRepositoryProvider).updateConfig(widget.id, next);
  }
}

