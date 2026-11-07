/// Heuristic token counter: no heavyweight tokenizer in v1.
///
/// Latin characters cost ~4 chars/token, Cyrillic ~2 chars/token, everything
/// else (CJK, emoji, ...) is counted as one token per character.
library;

int estimateTokens(String text) {
  if (text.isEmpty) return 0;
  var latin = 0;
  var cyrillic = 0;
  var other = 0;
  for (final rune in text.runes) {
    if ((rune >= 0x0400 && rune <= 0x04FF) || (rune >= 0x0500 && rune <= 0x052F)) {
      cyrillic++;
    } else if (rune < 0x80) {
      latin++;
    } else {
      other++;
    }
  }
  return (latin + 3) ~/ 4 + (cyrillic + 1) ~/ 2 + other;
}

/// Compact token display: `847`, `12.4K`, `1.05M`.
String formatTokenCount(int count) {
  if (count >= 1000000) {
    final m = count / 1000000;
    return '${m == m.roundToDouble() ? m.toInt() : m.toStringAsFixed(2)}M';
  }
  if (count >= 1000) {
    final k = count / 1000;
    return '${k == k.roundToDouble() ? k.toInt() : k.toStringAsFixed(1)}K';
  }
  return '$count';
}

/// Estimated tokens for a whole conversation.
///
/// Adds a small per-message overhead to account for the chat template
/// (role markers, separators) that real tokenizers also count.
int estimateConversationTokens(Iterable<String> messages, {int perMessageOverhead = 4}) {
  var total = 0;
  var count = 0;
  for (final message in messages) {
    total += estimateTokens(message);
    count++;
  }
  return total + count * perMessageOverhead;
}
