import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'code_block.dart';

/// Fullscreen HTML preview of one code block. Sibling CSS / JS blocks of
/// the same message are injected when the HTML itself lacks styles or
/// scripts, so multi-block answers (html + css + js) render as one page.
class HtmlPreviewScreen extends StatefulWidget {
  const HtmlPreviewScreen({
    super.key,
    required this.html,
    required this.snippets,
  });

  final String html;
  final List<CodeSnippet> snippets;

  @override
  State<HtmlPreviewScreen> createState() => _HtmlPreviewScreenState();
}

class _HtmlPreviewScreenState extends State<HtmlPreviewScreen> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..loadHtmlString(composePreviewHtml(widget.html, widget.snippets));
  }

  @override
  Widget build(BuildContext context) {
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
