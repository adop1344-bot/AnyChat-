import 'package:flutter/material.dart';

import '../../../../core/theme/app_tokens.dart';
import '../../domain/models.dart';

/// Tool calls read like a terminal log: mono, one line each, no boxes.
class ToolStepsView extends StatelessWidget {
  const ToolStepsView({super.key, required this.steps});

  final List<ToolStep> steps;

  @override
  Widget build(BuildContext context) {
    if (steps.isEmpty) return const SizedBox.shrink();
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpace.x2),
      padding: const EdgeInsets.only(left: AppSpace.x3),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (final ToolStep step in steps)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 1),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SizedBox(
                    width: 16,
                    child: Icon(
                      _icon(step.kind),
                      size: 12,
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(width: AppSpace.x1),
                  Expanded(
                    child: Text(
                      _line(step),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.figure(
                        11,
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

  static String _line(ToolStep step) {
    final String label = _label(step.kind);
    final String arg = step.argument.trim();
    final String tail = step.summary.trim();
    return <String>[
      label,
      if (arg.isNotEmpty) arg,
      if (tail.isNotEmpty) '· $tail',
    ].join(' ');
  }

  static IconData _icon(String kind) => switch (kind) {
        'SEARCH' => Icons.search,
        'OPEN' => Icons.link,
        'WIDGET' => Icons.widgets_outlined,
        'RUN' => Icons.terminal_outlined,
        _ => Icons.build_outlined,
      };

  static String _label(String kind) => switch (kind) {
        'SEARCH' => 'search',
        'OPEN' => 'open',
        'WIDGET' => 'widget',
        'RUN' => 'run',
        _ => kind.toLowerCase(),
      };
}
