// lib/services/tts_service.dart
// Native Android Text-to-Speech wrapper via platform channel (Zero 3rd party deps)

import 'package:flutter/services.dart';

class TtsService {
  static const _channel = MethodChannel('com.example.wortbit_de/tts');
  bool _isInitialized = false;

  Future<void> init() async {
    if (_isInitialized) return;
    try {
      await _channel.invokeMethod('init');
      _isInitialized = true;
    } catch (e) {
      // ignore: avoid_print
      print('[TTS] init error: $e');
    }
  }

  Future<void> speak(String text) async {
    try {
      await _channel.invokeMethod('speak', {'text': text});
    } catch (e) {
      // ignore: avoid_print
      print('[TTS] speak error: $e');
    }
  }

  Future<void> stop() async {
    try {
      await _channel.invokeMethod('stop');
    } catch (e) {
      // ignore: avoid_print
      print('[TTS] stop error: $e');
    }
  }

  Future<void> dispose() async {
    await stop();
  }
}
