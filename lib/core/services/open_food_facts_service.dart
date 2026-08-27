import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

import '../../data/models/food_models.dart';

class NutritionLookupException implements Exception {
  const NutritionLookupException(this.message);
  final String message;
}

class OpenFoodFactsService {
  OpenFoodFactsService._();
  static final instance = OpenFoodFactsService._();

  static const _searchEndpoint =
      'https://world.openfoodfacts.org/cgi/search.pl';

  Future<FoodNutrition?> lookup(String foodName) async {
    final uri = Uri.parse(_searchEndpoint).replace(
      queryParameters: {
        'search_terms': foodName,
        'search_simple': '1',
        'action': 'process',
        'json': '1',
        'page_size': '1',
      },
    );

    late final http.Response response;
    try {
      response = await http.get(uri).timeout(const Duration(seconds: 8));
    } on TimeoutException {
      throw const NutritionLookupException('Nutrition database timed out.');
    } on SocketException {
      throw const NutritionLookupException(
        'Nutrition database is unavailable.',
      );
    } catch (_) {
      throw const NutritionLookupException(
        'Nutrition database is unavailable.',
      );
    }
    if (response.statusCode != 200) {
      throw NutritionLookupException(
        'Nutrition database returned status ${response.statusCode}.',
      );
    }

    late final Map<String, dynamic> decoded;
    try {
      decoded = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw const NutritionLookupException(
        'Nutrition database response was invalid.',
      );
    }
    final products = (decoded['products'] as List?) ?? const [];
    if (products.isEmpty) return null;

    final product = products.first as Map<String, dynamic>;
    final nutriments = (product['nutriments'] as Map?)?.cast<String, dynamic>();
    if (nutriments == null) return null;

    final calories = (nutriments['energy-kcal_100g'] as num?)?.toDouble();
    if (calories == null) return null;

    return FoodNutrition(
      calories: calories,
      carbsG: (nutriments['carbohydrates_100g'] as num?)?.toDouble() ?? 0,
      fatG: (nutriments['fat_100g'] as num?)?.toDouble() ?? 0,
      proteinG: (nutriments['proteins_100g'] as num?)?.toDouble() ?? 0,
      dietaryStatus: _dietaryStatusOf(product),
      portionLabel: 'per 100g',
      portionWeightGrams: 100,
    );
  }

  DietaryStatus _dietaryStatusOf(Map<String, dynamic> product) {
    final labels =
        (product['labels_tags'] as List?)?.cast<String>() ?? const [];
    if (labels.any((l) => l.contains('halal'))) return DietaryStatus.halal;
    if (labels.any((l) => l.contains('haram'))) return DietaryStatus.haram;
    return DietaryStatus.unknown;
  }
}
