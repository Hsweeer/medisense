import 'dart:convert';
import 'package:http/http.dart' as http;

import '../../data/models/food_models.dart';

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

    final response = await http.get(uri);
    if (response.statusCode != 200) return null;

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
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
