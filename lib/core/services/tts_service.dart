import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Lets MedAI speak its replies out loud, so voice conversations feel
/// two-way instead of "you talk, it only types back."
///
/// Uses the on-device flutter_tts engine — completely free, works offline,
/// no API key and no per-character billing (unlike cloud TTS services).
/// This is a deliberate tradeoff: on-device voices are a little more
/// robotic than something like ElevenLabs, but they cost nothing and never
/// add network latency to a reply that's already finished generating.
class TtsService {
  TtsService._();
  static final TtsService instance = TtsService._();

  final FlutterTts _tts = FlutterTts();
  bool _ready = false;
  bool speaking = false;

  Future<void> _ensureReady() async {
    if (_ready) return;
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.48); // calmer, more "clinical assistant" pace than the 0.5 default
    await _tts.setPitch(1.0);
    await _tts.setVolume(1.0);
    _tts.setStartHandler(() => speaking = true);
    _tts.setCompletionHandler(() => speaking = false);
    _tts.setCancelHandler(() => speaking = false);
    _tts.setErrorHandler((msg) {
      debugPrint('[TtsService] error: $msg');
      speaking = false;
    });
    _ready = true;
  }

  /// Speaks [text] aloud. Cancels whatever it was saying before, so a new
  /// reply (or the user replaying an older bubble) never overlaps with the
  /// previous one.
  Future<void> speak(String text) async {
    final clean = _cleanForSpeech(text);
    if (clean.isEmpty) return;
    try {
      await _ensureReady();
      await _tts.stop();
      await _tts.speak(clean);
    } catch (e) {
      debugPrint('[TtsService] speak failed: $e');
      speaking = false;
    }
  }

  Future<void> stop() async {
    if (!_ready) return;
    try {
      await _tts.stop();
    } catch (_) {}
    speaking = false;
  }

  /// Strips things that read out awkwardly when spoken — bullet points,
  /// markdown emphasis, and stray emoji/warning glyphs — so "• Metformin
  /// (500mg)" is spoken as "Metformin, 500mg" instead of "bullet Metformin
  /// open paren 500 milligrams close paren".
  String _cleanForSpeech(String raw) {
    var t = raw;
    t = t.replaceAll('•', ',');
    t = t.replaceAll(RegExp(r'[*_#]'), '');
    t = t.replaceAll(RegExp(r'[⚠️▍]'), '');
    t = t.replaceAll(RegExp(r'\n+'), '. ');
    t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
    return t;
  }
}