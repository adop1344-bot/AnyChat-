import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/errors/api_error.dart';
import '../../../../core/errors/error_localizer.dart';
import '../../domain/models.dart';
import '../../../../l10n/app_localizations.dart';
import 'attachment_view.dart';
import 'tool_steps_view.dart';
import 'code_block.dart';

/// Compact `‹ 2/2 ›` switcher between regenerations of the same message.
typedef BranchPager = ({
  int current,
  int total,
  VoidCallback? onPrev,
  VoidCallback? onNext,
});

class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.streamingText,
    this.streamingReasoning = '',
    this.toolSteps = const <ToolStep>[],
    required this.isStreaming,
    required this.isLast,
    required this.showRegenerate,
    this.onEdit,
    this.onBranch,
    this.onRegenerate,
    this.branchPager,
  });

  final Message message;
  final String streamingText;
  final String streamingReasoning;
  final List<ToolStep> toolSteps;
  final bool isStreaming;
  final bool isLast;
  final bool showRegenerate;
  final VoidCallback? onEdit;
  final VoidCallback? onBranch;
  final VoidCallback? onRegenerate;
  final BranchPager? branchPager;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isUser = message.role == 'user';
    final text = isStreaming ? streamingText : message.content;
    final reasoning = isStreaming
        ? streamingReasoning
        : message.reasoning ?? '';
    final storedError = message.errorType;
    final error = storedError == null
        ? null
        : ApiError.fromStored(storedError, details: message.errorDetails);

    final showCopy = !isStreaming && message.content.trim().isNotEmpty;
    final wordCount = isUser || isStreaming || !showCopy
        ? 0
        : _countWords(message.content);
    final showBranch = onBranch != null && (isLast || branchPager != null);
    final hasActions = showCopy ||
        onEdit != null ||
        showBranch ||
        branchPager != null ||
        (onRegenerate != null && error == null);

    final generatingStyle = theme.textTheme.bodyMedium?.copyWith(
      fontStyle: FontStyle.italic,
      color: scheme.onSurfaceVariant,
    );

    final content = <Widget>[
      if (message.attachments.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: <Widget>[
              for (final attachment in message.attachments)
                AttachmentPreview(attachment: attachment),
            ],
          ),
        ),
      if (toolSteps.isNotEmpty) ToolStepsView(steps: toolSteps),
      if (reasoning.trim().isNotEmpty)
        _ThinkingBlock(reasoning: reasoning, live: isStreaming),
      if (isStreaming)
        text.isEmpty
            ? (reasoning.trim().isEmpty
                ? Text(l10n.generating, style: generatingStyle)
                : const SizedBox.shrink())
            : _MessageBody(
                content: text,
                isUser: isUser,
                streaming: true,
                messageId: message.id,
              )
      else if (message.content.isNotEmpty)
        _MessageBody(
          content: message.content,
          isUser: isUser,
          messageId: message.id,
        )
      else if (error == null)
        Text(l10n.generating, style: generatingStyle),
      if (error != null) ...<Widget>[
        const SizedBox(height: 6),
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(
                Icons.error_outline,
                size: 15,
                color: scheme.error,
              ),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                localizeApiError(l10n, error),
                style:
                    theme.textTheme.bodySmall?.copyWith(color: scheme.error),
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: TextButton.icon(
            onPressed: () => _copyContent(
              context,
              _errorReport(l10n, error),
            ),
            icon: const Icon(Icons.bug_report_outlined, size: 16),
            label: Text(l10n.copyError),
          ),
        ),
        if (showRegenerate)
          TextButton.icon(
            onPressed: onRegenerate,
            icon: const Icon(Icons.refresh, size: 16),
            label: Text(l10n.retry),
          ),
      ],
    ];

    final Widget bubble;
    if (isUser) {
      bubble = Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.82,
        ),
        padding: const EdgeInsets.fromLTRB(14, 8, 12, 6),
        decoration: BoxDecoration(
          color: scheme.primaryContainer,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: content,
        ),
      );
    } else {
      bubble = ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.88,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: content,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: Align(
        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment:
              isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: <Widget>[
            bubble,
            if (hasActions)
              Padding(
                padding: EdgeInsets.only(
                  top: 2,
                  bottom: 2,
                  left: isUser ? 0 : 4,
                  right: isUser ? 4 : 0,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    if (branchPager != null)
                      _BranchPager(pager: branchPager!),
                    if (wordCount > 0)
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Text(
                          l10n.wordCount(wordCount),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    if (showCopy)
                      IconButton(
                        onPressed: () =>
                            _copyContent(context, message.content),
                        tooltip: l10n.copy,
                        iconSize: 18,
                        visualDensity: VisualDensity.compact,
                        color: scheme.onSurfaceVariant,
                        icon: const Icon(Icons.content_copy),
                      ),
                    if (onEdit != null)
                      IconButton(
                        onPressed: onEdit,
                        tooltip: l10n.editMessage,
                        iconSize: 18,
                        visualDensity: VisualDensity.compact,
                        color: scheme.onSurfaceVariant,
                        icon: const Icon(Icons.edit_outlined),
                      ),
                    if (showBranch)
                      IconButton(
                        onPressed: onBranch,
                        tooltip: l10n.branchFromHere,
                        iconSize: 18,
                        visualDensity: VisualDensity.compact,
                        color: scheme.onSurfaceVariant,
                        icon: const Icon(Icons.account_tree_outlined),
                      ),
                    if (onRegenerate != null && error == null)
                      IconButton(
                        onPressed: onRegenerate,
                        tooltip: l10n.regenerate,
                        iconSize: 18,
                        visualDensity: VisualDensity.compact,
                        color: scheme.onSurfaceVariant,
                        icon: const Icon(Icons.refresh),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  static int _countWords(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return 0;
    return trimmed.split(RegExp(r'\s+')).length;
  }

  static String _errorReport(AppLocalizations l10n, ApiError error) {
    final buffer = StringBuffer()
      ..writeln('AnyChat+ error')
      ..writeln('type: ${error.type.name}');
    if (error.statusCode != null) buffer.writeln('http: ${error.statusCode}');
    if (error.details != null && error.details!.isNotEmpty) {
      buffer.writeln('details: ${error.details}');
    }
    if (error.raw.isNotEmpty) {
      final raw = error.raw.length > 2000
          ? '${error.raw.substring(0, 2000)}…'
          : error.raw;
      buffer.writeln('raw: $raw');
    }
    return buffer.toString().trimRight();
  }

  Future<void> _copyContent(BuildContext context, String content) async {
    await Clipboard.setData(ClipboardData(text: content));
    if (!context.mounted) return;
    final l10n = AppLocalizations.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.copied),
        duration: const Duration(seconds: 1),
      ),
    );
  }
}

class _BranchPager extends StatelessWidget {
  const _BranchPager({required this.pager});

  final BranchPager pager;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 30,
      margin: const EdgeInsets.only(right: 4),
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _arrow(context, Icons.chevron_left, pager.onPrev),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 1),
            child: Text(
              '${pager.current}/${pager.total}',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
          _arrow(context, Icons.chevron_right, pager.onNext),
        ],
      ),
    );
  }

  Widget _arrow(BuildContext context, IconData icon, VoidCallback? onTap) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: SizedBox(
        width: 30,
        height: 30,
        child: Icon(
          icon,
          size: 18,
          color: onTap == null ? scheme.outline : scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _MessageBody extends StatelessWidget {
  const _MessageBody({
    required this.content,
    required this.isUser,
    this.streaming = false,
    this.messageId,
  });

  final String content;
  final bool isUser;
  final bool streaming;
  final int? messageId;

  @override
  Widget build(BuildContext context) {
    if (isUser) {
      return SelectableText(content);
    }
    final theme = Theme.of(context);
    final data = streaming ? '$content▌' : content;
    return SelectionArea(
      child: MarkdownBody(
        data: data,
        onTapLink: (String text, String? href, String title) =>
            _openLink(context, href),
        builders: <String, MarkdownElementBuilder>{
          'pre': CodeBlockBuilder(
            snippets: extractCodeSnippets(content),
            messageId: messageId,
          ),
        },
        styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
          p: theme.textTheme.bodyMedium,
          code: theme.textTheme.bodySmall?.copyWith(
            fontFamily: 'monospace',
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
          ),
          codeblockDecoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          blockquoteDecoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHigh,
            border: Border(
              left: BorderSide(
                color: theme.colorScheme.outline,
                width: 3,
              ),
            ),
          ),
        ),
      ),
    );
  }

  static Future<void> _openLink(BuildContext context, String? href) async {
    if (href == null || href.isEmpty) return;
    final uri = Uri.tryParse(href);
    if (uri == null || !uri.hasScheme) return;
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) {
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.errUnknown(href))),
      );
    }
  }
}

class _ThinkingBlock extends StatefulWidget {
  const _ThinkingBlock({required this.reasoning, required this.live});

  final String reasoning;
  final bool live;

  @override
  State<_ThinkingBlock> createState() => _ThinkingBlockState();
}

class _ThinkingBlockState extends State<_ThinkingBlock> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final style = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
      fontStyle: FontStyle.italic,
      height: 1.35,
    );
    final label = widget.live && widget.reasoning.trim().isEmpty
        ? l10n.thinkingLive
        : l10n.thinking;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  widget.live ? Icons.psychology : Icons.psychology_outlined,
                  size: 14,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: style?.copyWith(fontStyle: FontStyle.normal),
                  ),
                ),
                Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  size: 16,
                  color: scheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
          if (!_expanded &&
              widget.live &&
              widget.reasoning.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2, left: 2),
              child: Text(
                widget.reasoning.trim().split('\n').last.trim(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style,
              ),
            ),
          if (_expanded && widget.reasoning.trim().isNotEmpty)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: 4),
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: scheme.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
              child: Text(widget.reasoning.trim(), style: style),
            ),
        ],
      ),
    );
  }
}
