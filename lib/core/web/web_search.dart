import 'package:dio/dio.dart';

class WebToolCall {
  final String kind;
  final String argument;
  final int start;

  const WebToolCall(this.kind, this.argument, this.start);

  static final RegExp _lineRe = RegExp(
    r'^[ \t]*(SEARCH|OPEN):[ \t]*(\S.*?)?[ \t]*$',
    multiLine: true,
  );

  static WebToolCall? extract(String content) {
    WebToolCall? last;
    for (final m in _lineRe.allMatches(content)) {
      final arg = (m.group(2) ?? '').trim();
      if (arg.isEmpty) continue;
      last = WebToolCall(m.group(1)!, arg, m.start);
    }
    return last;
  }

  static String stripToolLines(String content) =>
      content.split('\n').where((l) => !_lineRe.hasMatch(l)).join('\n');
}

class WebSearch {
  static final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 25),
      headers: <String, String>{
        'User-Agent':
            'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Mobile Safari/537.36',
        'Accept-Language': 'ru,en;q=0.8',
      },
      followRedirects: true,
      maxRedirects: 6,
    ),
  );

  static Future<String> run(WebToolCall call) async {
    try {
      if (call.kind == 'OPEN') return await openPage(call.argument);
      return await search(call.argument);
    } on DioException catch (e) {
      return 'Инструмент недоступен: ${e.message ?? e.type.name}. Отвечай без веба.';
    } catch (e) {
      return 'Инструмент недоступен: $e. Отвечай без веба.';
    }
  }

  static Future<String> search(String query) async {
    try {
      final bing = await _bingRss(query);
      if (bing != null) return bing;
    } catch (_) {}
    return _ddgLite(query);
  }

  static Future<String?> _bingRss(String query) async {
    final resp = await _dio.get<String>(
      'https://www.bing.com/search',
      queryParameters: <String, dynamic>{'q': query, 'format': 'rss'},
      options: Options(responseType: ResponseType.plain),
    );
    final xml = resp.data ?? '';
    final items = RegExp(r'<item>(.*?)</item>', dotAll: true)
        .allMatches(xml)
        .toList();
    if (items.isEmpty) return null;
    final b = StringBuffer('Результаты Bing по запросу "$query":\n');
    var i = 0;
    for (final m in items) {
      if (i >= 6) break;
      final block = m.group(1)!;
      final title = _xmlTag(block, 'title');
      final link = _xmlTag(block, 'link');
      final desc = _stripTags(_xmlTag(block, 'description'));
      if (link.isEmpty) continue;
      b.writeln('${i + 1}. ${title.isEmpty ? link : title}');
      b.writeln('   URL: $link');
      if (desc.isNotEmpty) {
        b.writeln('   ${desc.length > 320 ? desc.substring(0, 320) : desc}');
      }
      i++;
    }
    return i == 0 ? null : b.toString();
  }

  static String _xmlTag(String xml, String tag) {
    final m = RegExp('<$tag>(.*?)</$tag>', dotAll: true).firstMatch(xml);
    if (m == null) return '';
    return m.group(1)!
        .trim()
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll('&amp;', '&');
  }

  static Future<String> _ddgLite(String query) async {
    final resp = await _dio.get<String>(
      'https://lite.duckduckgo.com/lite/',
      queryParameters: <String, dynamic>{'q': query},
      options: Options(responseType: ResponseType.plain),
    );
    final html = resp.data ?? '';
    final links = <MapEntry<String, String>>[];
    final linkRe = RegExp(
      r'<a[^>]+href="(https?://[^"]+)"[^>]*class="result-link"[^>]*>(.*?)</a>',
      dotAll: true,
      caseSensitive: false,
    );
    for (final m in linkRe.allMatches(html)) {
      final title = _stripTags(m.group(2)!);
      if (title.isEmpty) continue;
      links.add(MapEntry(m.group(1)!, title));
    }
    if (links.isEmpty) {
      final altRe = RegExp(
        r'<a[^>]*rel="nofollow"[^>]*href="(https?://[^"]+)"[^>]*>(.*?)</a>',
        dotAll: true,
        caseSensitive: false,
      );
      for (final m in altRe.allMatches(html)) {
        final href = m.group(1)!;
        if (href.contains('duckduckgo.com')) continue;
        final title = _stripTags(m.group(2)!);
        if (title.isEmpty || title.length < 2) continue;
        links.add(MapEntry(href, title));
      }
    }
    final snippets = <String>[];
    for (final m
        in RegExp(r'class="result-snippet"[^>]*>(.*?)</td>', dotAll: true)
            .allMatches(html)) {
      snippets.add(_stripTags(m.group(1)!));
    }
    final b = StringBuffer('Результаты DuckDuckGo по запросу "$query":\n');
    if (links.isEmpty) {
      b.writeln('Ничего не найдено.');
    }
    var shown = 0;
    for (var i = 0; i < links.length && shown < 6; i++) {
      b.writeln('${shown + 1}. ${links[i].value}');
      b.writeln('   URL: ${links[i].key}');
      if (i < snippets.length && snippets[i].isNotEmpty) {
        b.writeln('   ${snippets[i]}');
      }
      shown++;
    }
    return b.toString();
  }

  static Future<String> openPage(String url) async {
    final resp = await _dio.get<String>(
      url,
      options: Options(responseType: ResponseType.plain),
    );
    var html = resp.data ?? '';
    html = html.replaceAll(
      RegExp(
        r'<(script|style|noscript|svg)[^>]*>.*?</\1>',
        dotAll: true,
        caseSensitive: false,
      ),
      ' ',
    );
    final text = _stripTags(html);
    final cut = text.length > 6000 ? text.substring(0, 6000) : text;
    return 'Текст страницы $url:\n$cut';
  }

  static String _stripTags(String html) {
    var out = html.replaceAll(RegExp(r'<[^>]+>'), ' ');
    out = out
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>');
    out = out.replaceAllMapped(
      RegExp('&#(\\d+);'),
      (m) => String.fromCharCode(int.parse(m.group(1)!)),
    );
    return out
        .replaceAll(RegExp(r'[ \t\r]+'), ' ')
        .replaceAll(RegExp(r'\n\s*\n+'), '\n')
        .trim();
  }
}
