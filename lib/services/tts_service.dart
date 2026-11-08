// lib/services/tts_service.dart
// Wrapper around flutter_tts for German pronunciation.

import 'package:flutter_tts/flutter_tts.dart';

class TtsService {
  final FlutterTts _tts = FlutterTts();
  bool _isInitialized = false;

  /// Call once before using [speak].
  Future<void> init() async {
    if (_isInitialized) return;

    await _tts.setLanguage('de-DE');
    await _tts.setSpeechRate(0.45);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);

    _tts.setErrorHandler((dynamic error) {
      // Silently swallow TTS errors; the button simply does nothing.
      // ignore: avoid_print
      print('[TTS] error: $error');
    });

    _isInitialized = true;
  }

  /// Pronounce [text] aloud in German.
  Future<void> speak(String text) async {
    if (!_isInitialized) await init();
    await _tts.stop();
    await _tts.speak(text);
  }

  /// Stop any ongoing speech immediately.
  Future<void> stop() async {
    await _tts.stop();
  }

  /// Release native resources. Call when the app is permanently dismissed.
  Future<void> dispose() async {
    await _tts.stop();
  }
}
