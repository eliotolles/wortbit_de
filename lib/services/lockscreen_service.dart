// lib/services/lockscreen_service.dart
// Flutter ↔ Native bridge for the LockScreen foreground service.

import 'package:flutter/services.dart';

class LockScreenService {
  static const _channel = MethodChannel('com.example.wortbit_de/lockscreen');

  /// Start the foreground service.
  static Future<void> start() async {
    try {
      await _channel.invokeMethod<void>('startService');
    } on PlatformException catch (e) {
      // ignore: avoid_print
      print('[LockScreen] startService error: ${e.message}');
    }
  }

  /// Stop the foreground service.
  static Future<void> stop() async {
    try {
      await _channel.invokeMethod<void>('stopService');
    } on PlatformException catch (e) {
      // ignore: avoid_print
      print('[LockScreen] stopService error: ${e.message}');
    }
  }

  /// Ẩn flashcard xuống để người dùng vào màn hình chính điện thoại
  static Future<void> dismiss() async {
    try {
      await _channel.invokeMethod<void>('dismiss');
    } on PlatformException catch (e) {
      // ignore: avoid_print
      print('[LockScreen] dismiss error: ${e.message}');
    }
  }
}
