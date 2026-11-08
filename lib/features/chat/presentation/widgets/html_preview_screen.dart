import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../state/chat_session.dart';
import 'code_block.dart';

/// Fullscreen HTML preview of one code block. Sibling CSS / JS blocks of
/// the same message are injected when the HTML itself lacks styles or
/// scripts, so multi-block answers (html + css + js) render as one page.
/// While the source message is still streaming, the preview rebuilds
/// itself from the live text: the page grows as the model writes.
class HtmlPreviewScreen extends ConsumerStatefulWidget {
  const HtmlPreviewScreen({
    super.key,
    required this.html,
    required this.snippets,
    this.messageId,
  });

  final String html;
  final List<CodeSnippet> snippets;
  final int? messageId;

  @override
  ConsumerState<HtmlPreviewScreen> createState() => _HtmlPreviewScreenState();
}

class _HtmlPreviewScreenState extends ConsumerState<HtmlPreviewScreen> {
  late final WebViewController _controller;
  Timer? _timer;
  String _applied = '';
  String _pending = '';
  String _lastRaw = '';

  @override
  void initState() {
    super.initState();
    _applied = composePreviewHtml(widget.html, widget.snippets);
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..loadHtmlString(_applied);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _currentHtml() {
    final session = ref.watch(chatSessionProvider);
    final live = session.isStreaming &&
        widget.messageId != null &&
        session.streamingMessageId == widget.messageId;
    if (live) {
      _lastRaw = session.streamText;
    }
    if (_lastRaw.isNotEmpty) {
      final snippets = extractCodeSnippets(_lastRaw);
      final htmlBlocks = <String>[
        for (final s in snippets)
          if (s.language == 'html') s.code,
      ];
      if (htmlBlocks.isNotEmpty && htmlBlocks.first.trim().isNotEmpty) {
        return composePreviewHtml(htmlBlocks.first, snippets);
      }
    }
    return composePreviewHtml(widget.html, widget.snippets);
  }

  void _scheduleApply(String html) {
    _pending = html;
    if (html == _applied) return;
    _timer ??= Timer(const Duration(milliseconds: 800), _flush);
  }

  Future<void> _flush() async {
    _timer = null;
    if (!mounted) return;
    if (_pending != _applied) {
      await _apply(_pending);
    }
    if (_pending != _applied) {
      _timer = Timer(const Duration(milliseconds: 800), _flush);
    }
  }

  Future<void> _apply(String html) async {
    _applied = html;
    var scroll = 0;
    try {
      final result = await _controller.runJavaScriptReturningResult(
        'window.scrollY || document.documentElement.scrollTop || 0',
      );
      scroll = int.tryParse('$result') ?? 0;
    } catch (_) {}
    try {
      await _controller.runJavaScript(
        'document.open();document.write(${jsonEncode(html)});'
        'document.close();window.scrollTo(0, $scroll);',
      );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    _scheduleApply(_currentHtml());
    return Scaffold(
      appBar: AppBar(title: const Text('HTML')),
      body: WebViewWidget(controller: _controller),
    );
  }
}

String composePreviewHtml(String html, List<CodeSnippet> snippets) {
  var doc = html;
  final css = snippets
      .where((s) => s.language == 'css' || s.language == 'scss')
      .map((s) => s.code)
      .join('\n');
  final js = snippets
      .where(
        (s) =>
            s.language == 'js' ||
            s.language == 'javascript' ||
            s.language == 'ts' ||
            s.language == 'typescript',
      )
      .map((s) => s.code)
      .join('\n');

  if (css.isNotEmpty &&
      !RegExp(r'<style\b', caseSensitive: false).hasMatch(doc)) {
    final tag = '<style>$css</style>';
    final headClose = RegExp(r'</head>', caseSensitive: false);
    doc = headClose.hasMatch(doc)
        ? doc.replaceFirst(headClose, '$tag</head>')
        : '$tag$doc';
  }
  if (js.isNotEmpty &&
      !RegExp(r'<script\b', caseSensitive: false).hasMatch(doc)) {
    final tag = '<script>$js</script>';
    final bodyClose = RegExp(r'</body>', caseSensitive: false);
    doc = bodyClose.hasMatch(doc)
        ? doc.replaceFirst(bodyClose, '$tag</body>')
        : '$doc$tag';
  }
  return doc;
}
