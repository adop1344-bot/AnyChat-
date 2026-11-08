/// Splits a streamed answer into visible content and hidden `<think>`
/// reasoning blocks emitted inline by qwen/deepseek-style models.
class ThinkSplitter {
  static const String _openTag = '<think>';
  static const String _closeTag = '</think>';

  static final RegExp _fullBlock =
      RegExp(r'<think>[\s\S]*?</think>\s*', caseSensitive: false);

  /// Removes reasoning from a stored message before resending it as history.
  static String stripThink(String source) {
    var out = source.replaceAll(_fullBlock, '');
    final open = out.indexOf('<think>');
    if (open >= 0) out = out.substring(0, open);
    return out;
  }

  String _buffer = '';
  bool _insideThink = false;

  ({String reasoning, String content}) feed(String chunk) {
    _buffer += chunk;
    return _drain(false);
  }

  ({String reasoning, String content}) close() => _drain(true);

  ({String reasoning, String content}) _drain(bool flush) {
    final reasoning = StringBuffer();
    final content = StringBuffer();
    var pos = 0;
    while (pos < _buffer.length) {
      if (!_insideThink && _buffer.startsWith('</think>', pos)) {
        pos += _closeTag.length;
        pos = _skipNewline(pos);
        continue;
      }
      final tag = _insideThink ? _closeTag : _openTag;
      final index = _buffer.indexOf(tag, pos);
      if (index == -1) {
        final safe = flush ? _buffer.length : _holdbackBoundary(pos);
        _emit(content, reasoning, _buffer.substring(pos, safe));
        _buffer = _buffer.substring(safe);
        return _result(reasoning, content);
      }
      _emit(content, reasoning, _buffer.substring(pos, index));
      _insideThink = !_insideThink;
      pos = index + tag.length;
      if (!_insideThink) pos = _skipNewline(pos);
    }
    _buffer = '';
    return _result(reasoning, content);
  }

  void _emit(StringBuffer content, StringBuffer reasoning, String chunk) {
    if (chunk.isEmpty) return;
    (_insideThink ? reasoning : content).write(chunk);
  }

  int _skipNewline(int pos) {
    if (pos < _buffer.length && _buffer.codeUnitAt(pos) == 13) pos += 1;
    if (pos < _buffer.length && _buffer.codeUnitAt(pos) == 10) pos += 1;
    return pos;
  }

  int _holdbackBoundary(int pos) {
    final tag = _insideThink ? _closeTag : _openTag;
    final windowStart =
        _buffer.length - (tag.length - 1) > pos
            ? _buffer.length - (tag.length - 1)
            : pos;
    for (var i = windowStart; i < _buffer.length; i++) {
      if (tag.startsWith(_buffer.substring(i))) return i;
    }
    return _buffer.length;
  }

  ({String reasoning, String content}) _result(
    StringBuffer reasoning,
    StringBuffer content,
  ) => (reasoning: reasoning.toString(), content: content.toString());
}
