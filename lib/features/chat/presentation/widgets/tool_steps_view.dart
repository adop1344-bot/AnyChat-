import 'package:flutter/material.dart';

import '../../domain/models.dart';

class ToolStepsView extends StatelessWidget {
  const ToolStepsView({super.key, required this.steps});

  final List<ToolStep> steps;

  @override
  Widget build(BuildContext context) {
    if (steps.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (final step in steps)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: <Widget>[
                  Icon(_icon(step.kind), size: 14, color: scheme.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${_label(step.kind)} ${step.argument.isEmpty ? '' : step.argument}'
                      '${step.summary.isEmpty ? '' : ' — ${step.summary}'}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static IconData _icon(String kind) => switch (kind) {
        'SEARCH' => Icons.search,
        'OPEN' => Icons.link,
        'WIDGET' => Icons.widgets_outlined,
        _ => Icons.build_outlined,
      };

  static String _label(String kind) => switch (kind) {
        'SEARCH' => 'Поиск:',
        'OPEN' => 'Страница:',
        'WIDGET' => 'Виджет:',
        _ => kind,
      };
}
