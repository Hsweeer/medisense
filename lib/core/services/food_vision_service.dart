import 'dart:convert';
import 'dart:io';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

class FoodIdentification {
  const FoodIdentification({
    required this.foodName,
    required this.estimatedPortion,
    required this.confident,
  });

  final String foodName;
  final String estimatedPortion;
  final bool confident;
}

class FoodVisionService {
  FoodVisionService._();
  static final instance = FoodVisionService._();

  static const _endpoint = 'https://api.groq.com/openai/v1/chat/completions';

  // Groq's vision-capable model lineup changes/deprecates often (llama-3.2
  // vision, then llama-4-scout, etc. were all decommissioned in turn).
  // Reading this from .env lets us swap models without a code change/redeploy
  // the next time Groq retires one, same pattern as OVERPASS_ENDPOINT_*.
  static const _fallbackModel = 'qwen/qwen3.6-27b';
  String get _model {
    final fromEnv = dotenv.env['GROQ_VISION_MODEL'];
    return (fromEnv != null && fromEnv.trim().isNotEmpty)
        ? fromEnv.trim()
        : _fallbackModel;
  }

  Future<FoodIdentification?> identify(File photo) async {
    final apiKey = dotenv.env['GROQ_API_KEY']?.trim() ?? '';
    if (apiKey.isEmpty) {
      throw StateError('GROQ_API_KEY missing from .env');
    }

    final bytes = await photo.readAsBytes();

    // Groq's /chat/completions endpoint is OpenAI-compatible: it takes a
    // plain JSON body, not multipart/form-data. There is no separate
    // "file upload" field for vision -- the image has to be base64-encoded
    // and embedded directly inside the message content as an image_url
    // data URL, alongside the text. The previous multipart version sent
    // the image nowhere the model could ever see it, so every call either
    // failed outright or came back "confident: false".
    final base64Image = base64Encode(bytes);

    final response = await http.post(
      Uri.parse(_endpoint),
      headers: {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'model': _model,
        'messages': [
          {
            'role': 'user',
            'content': [
              {
                'type': 'text',
                'text':
                'Identify the food in this photo and estimate its portion size. '
                    'Reply ONLY as JSON: {"foodName": "...", "estimatedPortion": "...", "confident": true|false}. '
                    'If you cannot confidently identify the food, set confident to false.',
              },
              {
                'type': 'image_url',
                'image_url': {
                  'url': 'data:image/jpeg;base64,$base64Image',
                },
              },
            ],
          },
        ],
      }),
    );

    if (response.statusCode != 200) {
      // Useful debug output when the API fails.
      // ignore: avoid_print
      print('FoodVisionService identify failed: ${response.statusCode} ${response.body}');
      return null;
    }

    try {
      final decoded = jsonDecode(response.body);
      final content = decoded['choices'][0]['message']['content'] as String;
      final clean = content
          .replaceAll('```json', '')
          .replaceAll('```', '')
          .trim();
      final parsed = jsonDecode(clean) as Map<String, dynamic>;

      return FoodIdentification(
        foodName: parsed['foodName'] ?? '',
        estimatedPortion: parsed['estimatedPortion'] ?? '1 serving',
        confident: parsed['confident'] ?? false,
      );
    } catch (_) {
      return null;
    }
  }
}