import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;

import '../../../../l10n/app_localizations.dart';
import 'html_preview_screen.dart';

/// A fenced code block extracted from a message.
typedef CodeSnippet = ({String language, String code});

/// All fenced blocks of a message; an HTML preview uses sibling CSS/JS
/// blocks written by the model as separate snippets.
List<CodeSnippet> extractCodeSnippets(String markdown) {
  final pattern = RegExp(
    r'```([A-Za-z0-9_+\-]*)[ \t]*\r?\n(.*?)```',
    dotAll: true,
    multiLine: true,
  );
  return <CodeSnippet>[
    for (final m in pattern.allMatches(markdown))
      (
        language: (m.group(1) ?? '').toLowerCase(),
        code: m.group(2) ?? '',
      ),
  ];
}

const Map<String, String> _kLanguageExt = <String, String>{
  'json': 'json',
  'html': 'html',
  'htm': 'html',
  'xml': 'xml',
  'svg': 'svg',
  'css': 'css',
  'scss': 'scss',
  'js': 'js',
  'javascript': 'js',
  'ts': 'ts',
  'typescript': 'ts',
  'jsx': 'jsx',
  'tsx': 'tsx',
  'dart': 'dart',
  'java': 'java',
  'kt': 'kt',
  'kotlin': 'kt',
  'swift': 'swift',
  'go': 'go',
  'rs': 'rs',
  'rust': 'rs',
  'py': 'py',
  'python': 'py',
  'rb': 'rb',
  'ruby': 'rb',
  'php': 'php',
  'c': 'c',
  'cpp': 'cpp',
  'c++': 'cpp',
  'cs': 'cs',
  'csharp': 'cs',
  'sh': 'sh',
  'bash': 'sh',
  'shell': 'sh',
  'zsh': 'sh',
  'sql': 'sql',
  'yaml': 'yaml',
  'yml': 'yaml',
  'toml': 'toml',
  'ini': 'ini',
  'conf': 'conf',
  'md': 'md',
  'markdown': 'md',
  'csv': 'csv',
  'txt': 'txt',
  'text': 'txt',
  'lua': 'lua',
  'r': 'r',
  'makefile': 'mk',
  'dockerfile': 'dockerfile',
};

const int _kCollapseThreshold = 16;

/// Custom `pre` builder: monospace card with a language header, copy /
/// save / preview actions and collapsing of long blocks.
///
/// Fenced blocks produced by models sometimes keep their fence markers
/// (indented or nested fences the parser treats as plain code) - those
/// stray fences are stripped here.
class CodeBlockBuilder extends MarkdownElementBuilder {
  CodeBlockBuilder({
    this.snippets = const <CodeSnippet>[],
    this.messageId,
  });

  final List<CodeSnippet> snippets;
  final int? messageId;

  @override
  bool isBlockElement() => true;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final code = _stripStrayFences(_textOf(element));
    if (code.trim().isEmpty) return null;
    final language = _languageOf(element, code);
    return CodeBlockCard(
      code: code,
      language: language,
      snippets: snippets,
      messageId: messageId,
    );
  }

  static String _languageOf(md.Element pre, String code) {
    for (final child in pre.children ?? const <md.Node>[]) {
      if (child is md.Element && child.tag == 'code') {
        final cls = child.attributes['class'] ?? '';
        final m = RegExp(r'language-([A-Za-z0-9_+\-]+)').firstMatch(cls);
        if (m != null) return m.group(1)!.toLowerCase();
      }
    }
    final t = code.trimLeft();
    if (t.startsWith('{') || t.startsWith('[')) return 'json';
    if (RegExp(r'^<!doctype html', caseSensitive: false).hasMatch(t)) {
      return 'html';
    }
    if (RegExp(r'^<[a-z!][\w-]*', caseSensitive: false).hasMatch(t)) {
      return 'html';
    }
    return '';
  }

  static String _textOf(md.Node node) {
    if (node is md.Text) return node.text;
    if (node is md.Element) {
      final buffer = StringBuffer();
      for (final child in node.children ?? const <md.Node>[]) {
        buffer.write(_textOf(child));
      }
      return buffer.toString();
    }
    return '';
  }

  static String _stripStrayFences(String raw) {
    var text = raw.replaceAll('\r\n', '\n');
    if (text.endsWith('\n')) {
      text = text.substring(0, text.length - 1);
    }
    final lines = text.split('\n');
    final fence = RegExp(r'^\s*(`{3,}|~{3,})');
    while (lines.isNotEmpty && fence.hasMatch(lines.first)) {
      lines.removeAt(0);
    }
    while (lines.isNotEmpty && fence.hasMatch(lines.last)) {
      lines.removeLast();
    }
    return lines.join('\n');
  }
}

class CodeBlockCard extends StatefulWidget {
  const CodeBlockCard({
    super.key,
    required this.code,
    required this.language,
    this.snippets = const <CodeSnippet>[],
    this.messageId,
  });

  final String code;
  final String language;
  final List<CodeSnippet> snippets;
  final int? messageId;

  @override
  State<CodeBlockCard> createState() => _CodeBlockCardState();
}

class _CodeBlockCardState extends State<CodeBlockCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context);
    final lines = widget.code.split('\n');
    final collapsible = lines.length > _kCollapseThreshold;
    final visibleLines = collapsible && !_expanded
        ? lines.sublist(0, _kCollapseThreshold)
        : lines;
    final isHtml = widget.language == 'html' || widget.language == 'htm';

    final codeStyle = theme.textTheme.bodySmall?.copyWith(
      fontFamily: 'monospace',
      height: 1.45,
    );

    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: scheme.outlineVariant),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(12, 2, 4, 2),
            child: Row(
              children: <Widget>[
                if (widget.language.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Text(
                      widget.language,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                const Spacer(),
                if (isHtml)
                  _Action(
                    icon: Icons.visibility_outlined,
                    tooltip: l10n.codePreview,
                    onTap: () => _openPreview(context),
                  ),
                _Action(
                  icon: Icons.save_outlined,
                  tooltip: l10n.codeSave,
                  onTap: () => _save(context),
                ),
                _Action(
                  icon: Icons.content_copy,
                  tooltip: l10n.copy,
                  onTap: () => _copy(context),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: AnimatedSize(
              duration: const Duration(milliseconds: 180),
              alignment: Alignment.topLeft,
              child: Stack(
                children: <Widget>[
                  Text(
                    visibleLines.join('\n'),
                    style: codeStyle,
                    softWrap: true,
                  ),
                  if (collapsible && !_expanded)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      height: 26,
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: <Color>[
                                scheme.surfaceContainerHighest.withValues(
                                  alpha: 0,
                                ),
                                scheme.surfaceContainerHighest,
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (collapsible)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: 6, bottom: 2),
                child: TextButton.icon(
                  onPressed: () => setState(() => _expanded = !_expanded),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    textStyle: theme.textTheme.labelMedium,
                  ),
                  icon: Icon(
                    _expanded
                        ? Icons.unfold_less_outlined
                        : Icons.unfold_more_outlined,
                    size: 16,
                  ),
                  label: Text(
                    _expanded
                        ? l10n.codeCollapse
                        : l10n.codeExpand(lines.length),
                  ),
                ),
              ),
            )
          else
            const SizedBox(height: 4),
        ],
      ),
    );
  }

  void _openPreview(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => HtmlPreviewScreen(
          html: widget.code,
          snippets: widget.snippets,
          messageId: widget.messageId,
        ),
      ),
    );
  }

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: widget.code));
    if (!context.mounted) return;
    _toast(context, AppLocalizations.of(context).copied);
  }

  Future<void> _save(BuildContext context) async {
    final ext = _kLanguageExt[widget.language] ?? 'txt';
    final uri = await FilePicker.saveFile(
      fileName: 'snippet.$ext',
      bytes: Uint8List.fromList(utf8.encode(widget.code)),
    );
    if (!context.mounted || uri == null) return;
    _toast(context, AppLocalizations.of(context).codeSaved);
  }

  void _toast(BuildContext context, String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), duration: const Duration(seconds: 2)),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(
            icon,
            size: 16,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
