import 'package:flutter/services.dart';

class ShareIntake {
  ShareIntake._();

  static const MethodChannel _channel = MethodChannel('app.anychat/shared');

  static Future<String?> consume() async {
    try {
      final text = await _channel.invokeMethod<String>('consume');
      if (text == null) return null;
      final trimmed = text.trim();
      return trimmed.isEmpty ? null : trimmed;
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  static void listen(void Function(String text) onText) {
    _channel.setMethodCallHandler((MethodCall call) async {
      if (call.method == 'sharedText' && call.arguments is String) {
        final trimmed = (call.arguments as String).trim();
        if (trimmed.isNotEmpty) onText(trimmed);
      }
    });
  }
}
