import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../config/api_keys.dart';

/// Thin wrapper around Groq's OpenAI-compatible chat completions and audio
/// transcription endpoints. Powers MedAI's free-text replies and real
/// voice-note transcription in [ChatProvider].
class GroqService {
  GroqService._();

  static const _chatEndpoint = 'https://api.groq.com/openai/v1/chat/completions';
  static const _transcribeEndpoint =
      'https://api.groq.com/openai/v1/audio/transcriptions';
  static const _model = 'llama-3.3-70b-versatile';
  static const _whisperModel = 'whisper-large-v3-turbo';

  static void _requireApiKey() {
    if (ApiKeys.groqApiKey.isEmpty ||
        ApiKeys.groqApiKey == 'PASTE_YOUR_GROQ_API_KEY_HERE') {
      throw Exception(
          'No Groq API key set — paste one in lib/core/config/api_keys.dart');
    }
  }

  /// [systemPrompt] sets MedAI's persona/instructions (with health-profile
  /// context folded in when personalization is on).
  /// [history] is the running conversation as {role, content} maps, oldest
  /// first, so MedAI has context beyond just the latest message.
  static Future<String> chat({
    required String systemPrompt,
    required List<Map<String, String>> history,
  }) async {
    _requireApiKey();

    final res = await http
        .post(
          Uri.parse(_chatEndpoint),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${ApiKeys.groqApiKey}',
          },
          body: jsonEncode({
            'model': _model,
            'messages': [
              {'role': 'system', 'content': systemPrompt},
              ...history,
            ],
            'temperature': 0.4,
            'max_tokens': 700,
          }),
        )
        .timeout(const Duration(seconds: 25));

    if (res.statusCode != 200) {
      throw Exception('Groq error ${res.statusCode}: ${res.body}');
    }

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final content =
        (data['choices'] as List?)?.first['message']?['content'];
    if (content is! String || content.trim().isEmpty) {
      throw Exception('Groq returned an empty response');
    }
    return content.trim();
  }

  /// Transcribes a recorded voice note to real text using Groq's hosted
  /// Whisper endpoint. This is genuine speech-to-text — not a scripted
  /// guess — but note it requires internet (unlike the on-device OCR).
  static Future<String> transcribeAudio(String audioFilePath) async {
    _requireApiKey();

    final file = File(audioFilePath);
    if (!await file.exists()) {
      throw Exception('Voice note file not found at $audioFilePath');
    }

    final request = http.MultipartRequest('POST', Uri.parse(_transcribeEndpoint))
      ..headers['Authorization'] = 'Bearer ${ApiKeys.groqApiKey}'
      ..fields['model'] = _whisperModel
      ..fields['response_format'] = 'json'
      ..files.add(await http.MultipartFile.fromPath('file', audioFilePath));

    final streamed = await request.send().timeout(const Duration(seconds: 40));
    final res = await http.Response.fromStream(streamed);

    if (res.statusCode != 200) {
      throw Exception('Groq transcription error ${res.statusCode}: ${res.body}');
    }

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final text = data['text'];
    if (text is! String || text.trim().isEmpty) {
      throw Exception('Groq returned an empty transcription');
    }
    return text.trim();
  }
}