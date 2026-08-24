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
  static const _model = 'llama-3.2-11b-vision-preview';

  Future<FoodIdentification?> identify(File photo) async {
    final apiKey = dotenv.env['GROQ_API_KEY'] ?? '';
    if (apiKey.isEmpty) {
      throw StateError('GROQ_API_KEY missing from .env');
    }

    final bytes = await photo.readAsBytes();
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
                'image_url': {'url': 'data:image/jpeg;base64,$base64Image'},
              },
            ],
          },
        ],
        'temperature': 0.2,
      }),
    );

    if (response.statusCode != 200) return null;

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
