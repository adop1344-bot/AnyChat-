import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart';

class TermuxShell {
  static const MethodChannel _channel = MethodChannel('anychat/termux');
  static const Duration _timeout = Duration(seconds: 150);
  static final Map<String, Completer<Map<String, dynamic>>> _pending =
      <String, Completer<Map<String, dynamic>>>{};
  static bool _handlerInstalled = false;

  static void _ensureHandler() {
    if (_handlerInstalled) return;
    _handlerInstalled = true;
    _channel.setMethodCallHandler((MethodCall call) async {
      if (call.method == 'onShellResult') {
        final args = Map<String, dynamic>.from(call.arguments as Map);
        final id = args['id'] as String?;
        if (id == null) return;
        final completer = _pending.remove(id);
        if (completer != null && !completer.isCompleted) {
          completer.complete(args);
        }
      }
    });
  }

  static Future<bool> available() async {
    try {
      return await _channel.invokeMethod<bool>('termuxCheck') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  static Future<String> run(String command) async {
    _ensureHandler();
    final id =
        '${DateTime.now().millisecondsSinceEpoch}${Random().nextInt(0xffff).toRadixString(16)}';
    final completer = Completer<Map<String, dynamic>>();
    _pending[id] = completer;
    final encoded = base64.encode(utf8.encode(command));
    final tmp = '/data/data/com.termux/files/home/.anychat-out-$id';
    final script = 'f=\'$tmp\'; '
        'echo $encoded | base64 -d | bash >\'\$f\' 2>&1; '
        'r=\${PIPESTATUS[1]}; '
        'b=\$(head -c 65536 \'\$f\' | base64 -w0); '
        'rm -f \'\$f\'; '
        'am broadcast -a com.anychat.fork.SHELL_RESULT '
        '--es id $id --ei rc \$r --es out "\$b" >/dev/null 2>&1';
    var sent = false;
    try {
      sent = await _channel.invokeMethod<bool>('termuxRun', <String, dynamic>{
        'script': script,
      }) ?? false;
    } on PlatformException {
      sent = false;
    } on MissingPluginException {
      sent = false;
    }
    if (!sent) {
      _pending.remove(id);
      return 'Инструмент недоступен: Termux не отвечает. Нужен Termux, '
          'allow-external-apps=true в ~/.termux/termux.properties '
          'и разрешение для AnyChat+.';
    }
    try {
      final res = await completer.future.timeout(_timeout);
      final rc = res['rc'];
      final encodedOut = (res['out'] ?? '').toString();
      var out = '';
      try {
        out = utf8.decode(base64.decode(encodedOut), allowMalformed: true);
      } on Exception {
        out = '';
      }
      return 'exit=$rc\n$out';
    } on TimeoutException {
      _pending.remove(id);
      return 'Таймаут ${_timeout.inSeconds} с: команда не вернулась. '
          'Возможно, в Termux нет am (pkg install termux-am), '
          'или разрешение ещё не выдано.';
    }
  }

  static String trimResult(String raw) {
    if (raw.length <= 4500) return raw;
    final head = raw.substring(0, 3500);
    final tail = raw.substring(raw.length - 800);
    return '$head\n…[обрезано]…\n$tail';
  }
}
