import 'package:anychat/core/storage/token_estimator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('estimateTokens', () {
    test('empty string is zero', () {
      expect(estimateTokens(''), 0);
    });

    test('latin: four chars per token (rounded up)', () {
      expect(estimateTokens('abcd'), 1);
      expect(estimateTokens('abc'), 1);
      expect(estimateTokens('abcdefgh'), 2);
      expect(estimateTokens('a'), 1);
    });

    test('cyrillic: two chars per token (rounded up)', () {
      expect(estimateTokens('привет'), 3);
      expect(estimateTokens('пр'), 1);
      expect(estimateTokens('п'), 1);
      expect(estimateTokens('сообщение'), 5);
    });

    test('mixed latin and cyrillic', () {
      // 'hi ' -> 3 latin chars -> 1 token, 'привет' -> 6 cyrillic chars -> 3.
      expect(estimateTokens('hi привет'), 4);
    });

    test('cjk and emoji count one token per char', () {
      expect(estimateTokens('你好'), 2);
      expect(estimateTokens('😀'), 1);
    });
  });

  group('formatTokenCount', () {
    test('formats hundreds, thousands and millions', () {
      expect(formatTokenCount(0), '0');
      expect(formatTokenCount(847), '847');
      expect(formatTokenCount(1000), '1K');
      expect(formatTokenCount(12400), '12.4K');
      expect(formatTokenCount(128000), '128K');
      expect(formatTokenCount(1000000), '1M');
      expect(formatTokenCount(1050000), '1.05M');
    });
  });

  group('estimateConversationTokens', () {
    test('sums messages plus per-message overhead', () {
      expect(
        estimateConversationTokens(<String>['abcd', 'abcd']),
        1 + 1 + 2 * 4,
      );
    });

    test('empty conversation without overhead', () {
      expect(estimateConversationTokens(<String>[]), 0);
    });
  });
}
