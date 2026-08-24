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

    // Use multipart/form-data so the image bytes are uploaded as a file
    final request = http.MultipartRequest('POST', Uri.parse(_endpoint));
    request.headers['Authorization'] = 'Bearer $apiKey';
    request.fields['model'] = _model;
    request.fields['messages'] = jsonEncode([
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
        ],
      },
    ]);

    request.files.add(http.MultipartFile.fromBytes('image', bytes,
        filename: 'photo.jpg'));

    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);

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
