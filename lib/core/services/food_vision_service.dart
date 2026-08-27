import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as image_lib;

import '../../data/models/food_models.dart';

enum FoodScanErrorType {
  invalidImage,
  authentication,
  rateLimited,
  timeout,
  network,
  noFood,
  lowConfidence,
  invalidResponse,
  api,
}

class FoodScanException implements Exception {
  const FoodScanException(this.type, this.message);
  final FoodScanErrorType type;
  final String message;
}

class FoodIdentification {
  const FoodIdentification({
    required this.foodName,
    required this.estimatedPortion,
    required this.estimatedWeightGrams,
    required this.confidence,
    required this.isFood,
  });

  final String foodName;
  final String estimatedPortion;
  final double? estimatedWeightGrams;
  final double confidence;
  final bool isFood;
}

class FoodVisionService {
  FoodVisionService._();
  static final instance = FoodVisionService._();

  static const _endpoint = 'https://api.groq.com/openai/v1/chat/completions';
  static const _fallbackModel = 'qwen/qwen3.6-27b';

  String get _model =>
      dotenv.env['GROQ_VISION_MODEL']?.trim().isNotEmpty == true
      ? dotenv.env['GROQ_VISION_MODEL']!.trim()
      : _fallbackModel;

  Future<FoodIdentification> identify(File photo) async {
    final image = await _prepareImage(photo);
    final content = await _request([
      {
        'type': 'text',
        'text':
            'Identify the main food in this photo. Ignore plates, tables, and background. '
            'For multiple foods, name the main meal. Estimate the visible portion and weight. '
            'Return ONLY JSON with foodName, category, estimatedPortion, estimatedWeightGrams, '
            'confidence (0 to 1), and isFood (true or false). Do not use markdown.',
      },
      {
        'type': 'image_url',
        'image_url': {'url': 'data:${image.mimeType};base64,${image.base64}'},
      },
    ]);
    final parsed = _parseObject(content);
    final isFood = _boolValue(parsed['isFood'], parsed['foodName'] != null);
    final confidence =
        _number(parsed['confidence']) ??
        (_boolValue(parsed['confident'], false) ? 0.8 : 0.0);
    final foodName = parsed['foodName']?.toString().trim() ?? '';
    if (!isFood || foodName.isEmpty) {
      throw const FoodScanException(
        FoodScanErrorType.noFood,
        'We could not identify a food in this photo.',
      );
    }
    if (confidence < 0.45) {
      throw const FoodScanException(
        FoodScanErrorType.lowConfidence,
        'We are not very confident about this food.',
      );
    }
    return FoodIdentification(
      foodName: foodName,
      estimatedPortion: parsed['estimatedPortion']?.toString() ?? '1 serving',
      estimatedWeightGrams: _number(parsed['estimatedWeightGrams']),
      confidence: confidence,
      isFood: isFood,
    );
  }

  Future<FoodNutrition> estimateNutrition(FoodIdentification food) async {
    final content = await _request([
      {
        'type': 'text',
        'text':
            'Estimate typical nutrition for ${food.foodName}, portion ${food.estimatedPortion}, '
            'weight ${food.estimatedWeightGrams ?? 'unknown'} grams. Return ONLY JSON with '
            'calories, proteinG, carbsG, fatG. Use reasonable typical values and no markdown.',
      },
    ]);
    final parsed = _parseObject(content);
    final calories = _number(parsed['calories']);
    final protein = _number(parsed['proteinG'] ?? parsed['protein']);
    final carbs = _number(parsed['carbsG'] ?? parsed['carbohydrates']);
    final fat = _number(parsed['fatG'] ?? parsed['fat']);
    if (calories == null || protein == null || carbs == null || fat == null) {
      throw const FoodScanException(
        FoodScanErrorType.invalidResponse,
        'Nutrition estimate was incomplete.',
      );
    }
    return FoodNutrition(
      calories: calories,
      proteinG: protein,
      carbsG: carbs,
      fatG: fat,
      dietaryStatus: DietaryStatus.unknown,
      portionLabel: food.estimatedPortion,
      isEstimated: true,
      portionWeightGrams: food.estimatedWeightGrams,
    );
  }

  Future<_PreparedImage> _prepareImage(File photo) async {
    if (!await photo.exists()) {
      throw const FoodScanException(
        FoodScanErrorType.invalidImage,
        'The photo could not be found.',
      );
    }
    final bytes = await photo.readAsBytes();
    if (bytes.isEmpty) {
      throw const FoodScanException(
        FoodScanErrorType.invalidImage,
        'The photo is empty.',
      );
    }
    final decoded = image_lib.decodeImage(bytes);
    if (decoded == null) {
      throw const FoodScanException(
        FoodScanErrorType.invalidImage,
        'The photo could not be read.',
      );
    }
    final resized = decoded.width > 1600
        ? image_lib.copyResize(decoded, width: 1600)
        : decoded;
    return _PreparedImage(
      base64: base64Encode(image_lib.encodeJpg(resized, quality: 85)),
      mimeType: 'image/jpeg',
    );
  }

  Future<String> _request(List<Map<String, dynamic>> content) async {
    final apiKey = dotenv.env['GROQ_API_KEY']?.trim() ?? '';
    if (apiKey.isEmpty) {
      throw const FoodScanException(
        FoodScanErrorType.authentication,
        'Food analysis is not configured.',
      );
    }
    try {
      final response = await http
          .post(
            Uri.parse(_endpoint),
            headers: {
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'model': _model,
              'messages': [
                {'role': 'user', 'content': content},
              ],
            }),
          )
          .timeout(const Duration(seconds: 30));
      if (response.statusCode == 401 || response.statusCode == 403) {
        throw const FoodScanException(
          FoodScanErrorType.authentication,
          'Food analysis authentication failed.',
        );
      }
      if (response.statusCode == 429) {
        throw const FoodScanException(
          FoodScanErrorType.rateLimited,
          'Food analysis is temporarily busy.',
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        debugPrint(
          '[FoodVisionService] API request failed with status ${response.statusCode}',
        );
        throw const FoodScanException(
          FoodScanErrorType.api,
          'Food analysis is temporarily unavailable.',
        );
      }
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final choices = decoded['choices'];
      String? text;
      if (choices is List && choices.isNotEmpty) {
        final firstChoice = choices.first;
        if (firstChoice is Map) {
          final message = firstChoice['message'];
          if (message is Map && message['content'] != null) {
            text = message['content'].toString();
          }
        }
      }
      if (text == null || text.trim().isEmpty) {
        throw const FoodScanException(
          FoodScanErrorType.invalidResponse,
          'Food analysis returned no result.',
        );
      }
      return text;
    } on FoodScanException {
      rethrow;
    } on SocketException {
      throw const FoodScanException(
        FoodScanErrorType.network,
        'Check your internet connection and try again.',
      );
    } on TimeoutException {
      throw const FoodScanException(
        FoodScanErrorType.timeout,
        'Food analysis is taking longer than expected.',
      );
    } on FormatException {
      throw const FoodScanException(
        FoodScanErrorType.invalidResponse,
        'Food analysis returned an invalid result.',
      );
    } catch (_) {
      throw const FoodScanException(
        FoodScanErrorType.network,
        'Food analysis could not be completed.',
      );
    }
  }

  Map<String, dynamic> _parseObject(String text) {
    final clean = text
        .replaceFirst(RegExp(r'^```(?:json)?\s*'), '')
        .replaceFirst(RegExp(r'\s*```$'), '')
        .trim();
    final start = clean.indexOf('{');
    final end = clean.lastIndexOf('}');
    if (start < 0 || end <= start) {
      throw const FoodScanException(
        FoodScanErrorType.invalidResponse,
        'Food analysis returned invalid JSON.',
      );
    }
    try {
      return jsonDecode(clean.substring(start, end + 1))
          as Map<String, dynamic>;
    } catch (_) {
      throw const FoodScanException(
        FoodScanErrorType.invalidResponse,
        'Food analysis returned invalid JSON.',
      );
    }
  }

  double? _number(Object? value) => value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '');
  bool _boolValue(Object? value, bool fallback) => value is bool
      ? value
      : (value?.toString().toLowerCase() == 'true' ? true : fallback);
}

class _PreparedImage {
  const _PreparedImage({required this.base64, required this.mimeType});
  final String base64;
  final String mimeType;
}
