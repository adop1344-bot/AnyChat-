import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/errors/api_error.dart';
import '../../../../core/storage/token_estimator.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/ui/atoms.dart';
import '../../domain/models.dart';
import '../../../../l10n/app_localizations.dart';
import 'attachment_view.dart';
import 'code_block.dart';
import 'tool_steps_view.dart';

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
    final bool isUser = message.role == 'user';
    final String text = isStreaming ? streamingText : message.content;
    final String reasoning =
        isStreaming ? streamingReasoning : message.reasoning ?? '';
    final String? storedError = message.errorType;
    final ApiError? error = storedError == null
        ? null
        : ApiError.fromStored(storedError, details: message.errorDetails);

    final bool showCopy = !isStreaming && message.content.trim().isNotEmpty;
    final int wordCount =
        isUser || isStreaming || !showCopy ? 0 : _countWords(message.content);
    final String? metricsLine = isUser || isStreaming ? null : _metricsLine(message);
    final bool showBranch = onBranch != null && (isLast || branchPager != null);
    final bool hasActions = showCopy ||
        onEdit != null ||
        showBranch ||
        branchPager != null ||
        (onRegenerate != null && error == null);

    final TextStyle generatingStyle = theme.textTheme.bodyMedium!.copyWith(
      color: scheme.onSurfaceVariant,
    );

    final List<Widget> content = <Widget>[
      if (message.attachments.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.x2),
          child: Wrap(
            spacing: AppSpace.x2,
            runSpacing: AppSpace.x2,
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
      if (error != null)
        _ErrorBlock(
          error: error,
          showRetry: showRegenerate,
          onRetry: onRegenerate,
          onCopy: () =>
              _copyContent(context, _errorReport(l10n, error)),
        ),
    ];

    final Widget body;
    if (isUser) {
      body = Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.82,
        ),
        padding: const EdgeInsets.fromLTRB(
          AppSpace.x3 + 2,
          AppSpace.x2 + 2,
          AppSpace.x3 + 2,
          AppSpace.x2 + 2,
        ),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: content,
        ),
      );
    } else {
      body = ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.9,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: content,
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpace.x4,
        isUser ? AppSpace.x3 : AppSpace.x4,
        AppSpace.x4,
        isUser ? 0 : AppSpace.x2,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment:
            isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: <Widget>[
          body,
          if (hasActions)
            Padding(
              padding: EdgeInsets.only(
                top: AppSpace.x1,
                left: isUser ? 0 : 0,
                right: isUser ? 0 : 0,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (branchPager != null) _BranchPager(pager: branchPager!),
                  if (metricsLine != null) ...<Widget>[
                    Figure(metricsLine, size: 10.5),
                    const SizedBox(width: AppSpace.x2),
                  ],
                  if (wordCount > 0) ...<Widget>[
                    Figure(
                      l10n.wordCount(wordCount),
                      size: 10.5,
                    ),
                    const SizedBox(width: AppSpace.x2),
                  ],
                  if (showCopy)
                    QuietIconButton(
                      icon: Icons.content_copy,
                      tooltip: l10n.copy,
                      box: 30,
                      size: 15,
                      onPressed: () => _copyContent(context, message.content),
                    ),
                  if (onEdit != null)
                    QuietIconButton(
                      icon: Icons.edit_outlined,
                      tooltip: l10n.editMessageTitle,
                      box: 30,
                      size: 15,
                      onPressed: onEdit,
                    ),
                  if (showBranch)
                    QuietIconButton(
                      icon: Icons.call_split,
                      tooltip: l10n.branchFromHere,
                      box: 30,
                      size: 15,
                      onPressed: onBranch,
                    ),
                  if (onRegenerate != null && error == null)
                    QuietIconButton(
                      icon: Icons.refresh,
                      tooltip: l10n.regenerate,
                      box: 30,
                      size: 15,
                      onPressed: onRegenerate,
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static String _rawErrorText(ApiError error) {
    var text = error.raw.trim();
    if (text.isEmpty) text = error.details?.trim() ?? '';
    if (text.length > 1000) text = '${text.substring(0, 1000)}…';
    return text;
  }

  /// `↓1.2K ↑340 · 18.4 tok/s`. A leading `~` marks heuristic numbers.
  static String? _metricsLine(Message message) {
    final tin = message.tokensIn;
    final tout = message.tokensOut;
    if (tin == null && tout == null) return null;
    final mark = message.tokensEstimated ? '~' : '';
    final parts = <String>[
      if (tin != null) '↓$mark${formatTokenCount(tin)}',
      if (tout != null) '↑$mark${formatTokenCount(tout)}',
    ];
    final ms = message.durationMs;
    if (tout != null && ms != null && ms > 0) {
      final tps = tout * 1000 / ms;
      parts.add('${tps.toStringAsFixed(1)} tok/s');
    }
    return parts.join(' · ');
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

/// Failures are part of the transcript: a hairline block with the status line
/// in mono and the raw body underneath, not a red banner.
class _ErrorBlock extends StatelessWidget {
  const _ErrorBlock({
    required this.error,
    required this.showRetry,
    required this.onRetry,
    required this.onCopy,
  });

  final ApiError error;
  final bool showRetry;
  final VoidCallback? onRetry;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final raw = MessageBubble._rawErrorText(error);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: AppSpace.x2),
      padding: const EdgeInsets.fromLTRB(
        AppSpace.x3,
        AppSpace.x2 + 2,
        AppSpace.x3,
        AppSpace.x2,
      ),
      decoration: BoxDecoration(
        color: scheme.error.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: scheme.error.withValues(alpha: 0.24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              StatusDot(color: scheme.error, size: 5),
              const SizedBox(width: AppSpace.x2),
              Figure(
                'HTTP ${error.statusCode ?? '-'} · ${error.type.name}',
                size: 11,
                weight: FontWeight.w500,
                color: scheme.error,
              ),
            ],
          ),
          if (raw.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: AppSpace.x1),
              child: Text(
                raw,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: AppType.figure(
                  11,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          const SizedBox(height: AppSpace.x1),
          Row(
            children: <Widget>[
              TextButton(
                onPressed: onCopy,
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  foregroundColor: scheme.onSurfaceVariant,
                ),
                child: Text(l10n.copyError),
              ),
              if (showRetry)
                TextButton(
                  onPressed: onRetry,
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                  child: Text(l10n.retry),
                ),
            ],
          ),
        ],
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
      height: 26,
      margin: const EdgeInsets.only(right: AppSpace.x2),
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _arrow(context, Icons.chevron_left, pager.onPrev),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Figure(
              '${pager.current}/${pager.total}',
              size: 10.5,
              weight: FontWeight.w500,
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
      child: SizedBox(
        width: 26,
        height: 26,
        child: Icon(
          icon,
          size: 15,
          color: onTap == null
              ? scheme.onSurfaceVariant.withValues(alpha: 0.35)
              : scheme.onSurfaceVariant,
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
    final theme = Theme.of(context);
    if (isUser) {
      return SelectableText(
        content,
        style: theme.textTheme.bodyMedium,
      );
    }
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
          h1: theme.textTheme.headlineSmall,
          h2: theme.textTheme.titleLarge,
          h3: theme.textTheme.titleMedium,
          h4: theme.textTheme.titleSmall,
          a: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.primary,
            decoration: TextDecoration.underline,
            decorationColor: theme.colorScheme.primary.withValues(alpha: 0.4),
          ),
          code: AppType.figure(
            12.5,
            color: theme.colorScheme.onSurface,
          ).copyWith(
            backgroundColor: theme.colorScheme.surfaceContainerHigh,
          ),
          codeblockDecoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(AppRadius.control),
          ),
          blockquoteDecoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: theme.colorScheme.outlineVariant,
                width: 2,
              ),
            ),
          ),
          blockquotePadding: const EdgeInsets.only(left: AppSpace.x3),
          horizontalRuleDecoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
          ),
          listBullet: theme.textTheme.bodyMedium,
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

/// Reasoning stays out of the answer but never out of sight: one quiet line
/// that expands in place.
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
    final TextStyle style = AppType.figure(
      11.5,
      height: 1.5,
      color: scheme.onSurfaceVariant,
    );
    final String label = widget.live && widget.reasoning.trim().isEmpty
        ? l10n.thinkingLive
        : l10n.thinking;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.x2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  StatusDot(
                    color: widget.live
                        ? scheme.primary
                        : scheme.onSurfaceVariant.withValues(alpha: 0.5),
                    size: 5,
                  ),
                  const SizedBox(width: AppSpace.x2),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: style,
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 14,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          if (!_expanded && widget.live && widget.reasoning.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                widget.reasoning.trim().split('\n').last.trim(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style,
              ),
            ),
          if (_expanded)
            Container(
              margin: const EdgeInsets.only(top: AppSpace.x1),
              padding: const EdgeInsets.only(left: AppSpace.x3),
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(color: scheme.outlineVariant),
                ),
              ),
              child: Text(widget.reasoning.trim(), style: style),
            ),
        ],
      ),
    );
  }
}
