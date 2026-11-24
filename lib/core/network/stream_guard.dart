import 'dart:io';

import 'package:flutter/services.dart';

class StreamGuard {
  static const MethodChannel _channel = MethodChannel('anychat/stream_guard');
  static bool _active = false;

  /// Starts the foreground service that keeps generation alive when the app
  /// leaves the screen. Callers pass the user's setting; off means no service.
  static Future<void> begin({bool enabled = true}) async {
    if (!Platform.isAndroid || _active) return;
    if (!enabled) return;
    _active = true;
    try {
      await _channel.invokeMethod<void>('start');
    } on MissingPluginException {
      // native side unavailable — generation still works without the service
    } on PlatformException {
      _active = false;
    }
  }

  static Future<void> end() async {
    if (!Platform.isAndroid || !_active) return;
    _active = false;
    try {
      await _channel.invokeMethod<void>('stop');
    } catch (_) {}
  }
}
