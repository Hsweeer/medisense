import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

import '../../data/models/food_models.dart';

class NutritionLookupException implements Exception {
  const NutritionLookupException(this.message);
  final String message;
}

/// Result of a successful barcode lookup — carries the product name
/// alongside its nutrition so the caller doesn't need a separate
/// vision/name-identification step.
class BarcodeProduct {
  const BarcodeProduct({required this.name, required this.nutrition});

  final String name;
  final FoodNutrition nutrition;
}

class OpenFoodFactsService {
  OpenFoodFactsService._();
  static final instance = OpenFoodFactsService._();

  static const _searchEndpoint =
      'https://world.openfoodfacts.org/cgi/search.pl';
  static const _productEndpoint =
      'https://world.openfoodfacts.org/api/v2/product';

  /// Ingredient keywords that make a product non-halal when no explicit
  /// halal certification is present. Kept lowercase for matching against
  /// the lowercased ingredients text.
  static const _haramKeywords = [
    'pork',
    'porcine',
    'swine',
    'pig fat',
    'bacon',
    'ham',
    'lard',
    'alcohol',
    'ethanol',
    'wine',
    'beer',
    'rum',
    'brandy',
    'liqueur',
    'gelatin',
    'gelatine',
  ];

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
    return _nutritionFromProduct(product);
  }

  /// Looks up a scanned barcode (EAN/UPC) directly against Open Food
  /// Facts' per-product endpoint and returns both the product name and
  /// its nutrition (with dietary/halal status), or `null` if that
  /// barcode isn't in the database.
  Future<BarcodeProduct?> lookupByBarcode(String barcode) async {
    final code = barcode.trim();
    if (code.isEmpty) return null;

    final uri = Uri.parse('$_productEndpoint/$code.json').replace(
      queryParameters: {
        'fields':
            'product_name,nutriments,labels_tags,traces_tags,'
            'ingredients_text,ingredients_text_en,quantity',
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

    if (decoded['status'] != 1) return null;
    final product = (decoded['product'] as Map?)?.cast<String, dynamic>();
    if (product == null) return null;

    final nutrition = _nutritionFromProduct(product);
    if (nutrition == null) return null;

    final name = (product['product_name'] as String?)?.trim();
    return BarcodeProduct(
      name: (name == null || name.isEmpty) ? 'Scanned product' : name,
      nutrition: nutrition,
    );
  }

  FoodNutrition? _nutritionFromProduct(Map<String, dynamic> product) {
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

  /// Determines halal / haram / unknown status for a product:
  /// 1. An explicit "halal" or "haram/pork/non-halal" label tag wins
  ///    outright — these come from certification data on Open Food Facts.
  /// 2. Otherwise, the ingredients text (and trace-allergen tags) are
  ///    scanned for known non-halal ingredients (pork, alcohol, plain
  ///    gelatin, etc.) — if found, the product is flagged haram.
  /// 3. If ingredients are available and none of the above match, the
  ///    product is treated as halal.
  /// 4. If there isn't enough data to judge (no labels and no ingredient
  ///    text), the status is left unknown/unverified.
  DietaryStatus _dietaryStatusOf(Map<String, dynamic> product) {
    final labels =
        (product['labels_tags'] as List?)?.cast<String>() ?? const [];
    if (labels.any((l) => l.contains('halal'))) return DietaryStatus.halal;
    if (labels.any((l) => l.contains('haram') || l.contains('non-halal'))) {
      return DietaryStatus.haram;
    }

    final traces =
        (product['traces_tags'] as List?)?.cast<String>() ?? const [];
    if (traces.any((t) => t.contains('pork') || t.contains('alcohol'))) {
      return DietaryStatus.haram;
    }

    final ingredientsText = [
      (product['ingredients_text_en'] as String?) ?? '',
      (product['ingredients_text'] as String?) ?? '',
    ].join(' ').toLowerCase();

    if (ingredientsText.trim().isEmpty) return DietaryStatus.unknown;

    final hasHaramIngredient = _haramKeywords.any(ingredientsText.contains);
    return hasHaramIngredient ? DietaryStatus.haram : DietaryStatus.halal;
  }
}
