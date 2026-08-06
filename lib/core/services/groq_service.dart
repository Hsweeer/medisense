import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_keys.dart';

/// Thin wrapper around Groq's OpenAI-compatible chat completions endpoint.
/// Used to power MedAI's free-text replies in [ChatProvider].
class GroqService {
  GroqService._();

  static const _endpoint = 'https://api.groq.com/openai/v1/chat/completions';
  static const _model = 'llama-3.3-70b-versatile';

  /// [systemPrompt] sets MedAI's persona/instructions (with health-profile
  /// context folded in when personalization is on).
  /// [history] is the running conversation as {role, content} maps, oldest
  /// first, so MedAI has context beyond just the latest message.
  static Future<String> chat({
    required String systemPrompt,
    required List<Map<String, String>> history,
  }) async {
    if (ApiKeys.groqApiKey.trim().isEmpty) {
      throw Exception(
        'No Groq API key set. Start the app with --dart-define=GROQ_API_KEY=your_key.',
      );
    }

    final res = await http
        .post(
          Uri.parse(_endpoint),
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
}
