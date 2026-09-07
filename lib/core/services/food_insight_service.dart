import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

import '../../data/models/food_models.dart';
import '../../data/models/models.dart';

class FoodInsightService {
  FoodInsightService._();
  static final instance = FoodInsightService._();

  static const _endpoint = 'https://api.groq.com/openai/v1/chat/completions';

  // 'llama-3.3-70b-versatile' was decommissioned by Groq on Aug 16, 2026 —
  // every call with that model now returns a 400 "model_decommissioned"
  // error, which is exactly why this note always fell back to "Could not
  // generate a personalized note right now." This is the same production
  // text model FoodVisionService.estimateNutrition and GroqService (MedAI
  // chat) already use successfully elsewhere in the app.
  static const _model = 'openai/gpt-oss-20b';

  Future<String> generateInsight({
    required String foodName,
    required FoodNutrition nutrition,
    required HealthProfile profile,
  }) async {
    final apiKey = dotenv.env['GROQ_API_KEY']?.trim() ?? '';
    if (apiKey.isEmpty) {
      return 'Insight unavailable - missing API configuration.';
    }

    final prompt =
        '''
Food: $foodName (${nutrition.portionLabel})
Calories: ${nutrition.calories.toStringAsFixed(0)}
Carbs: ${nutrition.carbsG.toStringAsFixed(0)}g
Fat: ${nutrition.fatG.toStringAsFixed(0)}g
Protein: ${nutrition.proteinG.toStringAsFixed(0)}g

User conditions: ${profile.conditions.join(', ')}
User allergies: ${profile.allergies.join(', ')}
User medications: ${profile.medications.join(', ')}

Write a short (1-2 sentence), friendly, advisory note about this food for
this specific user based on their health profile. This is guidance, not a
medical order - do not tell them they cannot eat it, just advise caution
where relevant.
''';

    late final http.Response response;
    try {
      response = await http
          .post(
            Uri.parse(_endpoint),
            headers: {
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'model': _model,
              'messages': [
                {'role': 'user', 'content': prompt},
              ],
              'temperature': 0.4,
            }),
          )
          .timeout(const Duration(seconds: 20));
    } catch (_) {
      // Network error / timeout — never let a failed insight note block
      // the rest of the food-review screen from working.
      return 'Could not generate a personalized note right now.';
    }

    if (response.statusCode != 200) {
      return 'Could not generate a personalized note right now.';
    }

    try {
      final decoded = jsonDecode(response.body);
      final content = decoded['choices'][0]['message']['content'];
      final text = (content as String).trim();
      return text.isEmpty
          ? 'Could not generate a personalized note right now.'
          : text;
    } catch (_) {
      return 'Could not generate a personalized note right now.';
    }
  }
}
