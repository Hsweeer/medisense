import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

import '../../data/models/food_models.dart';
import '../../data/models/models.dart';

class FoodInsightService {
  FoodInsightService._();
  static final instance = FoodInsightService._();

  static const _endpoint = 'https://api.groq.com/openai/v1/chat/completions';
  static const _model = 'llama-3.3-70b-versatile';

  Future<String> generateInsight({
    required String foodName,
    required FoodNutrition nutrition,
    required HealthProfile profile,
  }) async {
    final apiKey = dotenv.env['GROQ_API_KEY'] ?? '';
    if (apiKey.isEmpty) {
      return 'Insight unavailable â€” missing API configuration.';
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
medical order â€” do not tell them they cannot eat it, just advise caution
where relevant.
''';

    final response = await http.post(
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
    );

    if (response.statusCode != 200) {
      return 'Could not generate a personalized note right now.';
    }

    final decoded = jsonDecode(response.body);
    return (decoded['choices'][0]['message']['content'] as String).trim();
  }
}

