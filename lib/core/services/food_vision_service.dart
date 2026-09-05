// lib/core/services/food_vision_service.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as image_lib;
import 'package:image_picker/image_picker.dart';

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

  String get _model {
    final configured = dotenv.env['GROQ_VISION_MODEL']?.trim() ?? '';
    return configured == 'qwen/qwen3.6-27b' || configured == 'qwen/qwen3.8-27b'
        ? configured
        : _fallbackModel;
  }

  Future<FoodIdentification> identify(File photo) async {
    return identifyBytes(await photo.readAsBytes());
  }

  Future<FoodIdentification> identifyXFile(XFile photo) async {
    return identifyBytes(await photo.readAsBytes());
  }

  Future<FoodIdentification> identifyBytes(List<int> bytes) async {
    final image = _prepareImage(bytes);
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
      estimatedPortion:
          parsed['estimatedPortion']?.toString().trim().isNotEmpty == true
          ? parsed['estimatedPortion'].toString().trim()
          : '1 serving',
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
            'Estimate nutrition for "${food.foodName}", portion: ${food.estimatedPortion}'
            '${food.estimatedWeightGrams != null ? ' (~${food.estimatedWeightGrams!.round()}g)' : ''}. '
            'Return ONLY JSON with calories (number), carbsG (number), fatG (number), '
            'proteinG (number), dietaryStatus ("halal", "haram", or "unknown"), and '
            'portionLabel (string). Do not use markdown.',
      },
    ]);
    final parsed = _parseObject(content);
    final calories = _number(parsed['calories']);
    if (calories == null) {
      throw const FoodScanException(
        FoodScanErrorType.invalidResponse,
        'Could not estimate nutrition for this food.',
      );
    }
    return FoodNutrition(
      calories: calories,
      carbsG: _number(parsed['carbsG']) ?? 0,
      fatG: _number(parsed['fatG']) ?? 0,
      proteinG: _number(parsed['proteinG']) ?? 0,
      dietaryStatus: _dietaryStatusFrom(parsed['dietaryStatus']?.toString()),
      portionLabel: parsed['portionLabel']?.toString().trim().isNotEmpty == true
          ? parsed['portionLabel'].toString().trim()
          : food.estimatedPortion,
      portionWeightGrams: food.estimatedWeightGrams,
    );
  }

  DietaryStatus _dietaryStatusFrom(String? value) {
    switch (value?.toLowerCase().trim()) {
      case 'halal':
        return DietaryStatus.halal;
      case 'haram':
        return DietaryStatus.haram;
      default:
        return DietaryStatus.unknown;
    }
  }

  double? _number(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  bool _boolValue(dynamic value, bool fallback) {
    if (value == null) return fallback;
    if (value is bool) return value;
    final s = value.toString().toLowerCase().trim();
    if (s == 'true') return true;
    if (s == 'false') return false;
    return fallback;
  }

  _PreparedImage _prepareImage(List<int> bytes) {
    image_lib.Image? decoded;
    try {
      decoded = image_lib.decodeImage(Uint8List.fromList(bytes));
    } catch (_) {
      decoded = null;
    }
    if (decoded == null) {
      throw const FoodScanException(
        FoodScanErrorType.invalidImage,
        'This photo could not be read. Please try another one.',
      );
    }
    final resized = decoded.width > 1600
        ? image_lib.copyResize(decoded, width: 1600)
        : decoded;
    return _PreparedImage(
      base64: base64Encode(
        Uint8List.fromList(image_lib.encodeJpg(resized, quality: 85)),
      ),
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

    // qwen/qwen3.6-27b is currently served by Groq as a "preview" model
    // (their only vision-capable option after retiring the Llama vision
    // preview models), which carries much tighter rate limits than their
    // production models. A 429 here is frequently transient — a couple of
    // short, backed-off retries clears most of them without the user ever
    // seeing an error.
    const maxAttempts = 3;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
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
                'response_format': {'type': 'json_object'},
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
          if (attempt < maxAttempts) {
            // Prefer the server's own Retry-After hint when present;
            // otherwise back off a little longer on each retry.
            final retryAfterHeader = response.headers['retry-after'];
            final retryAfterSeconds = int.tryParse(retryAfterHeader ?? '');
            final wait = retryAfterSeconds != null
                ? Duration(seconds: retryAfterSeconds.clamp(1, 5))
                : Duration(milliseconds: 700 * attempt);
            debugPrint(
              '[FoodVisionService] rate limited (attempt $attempt/$maxAttempts) '
              '— retrying in ${wait.inMilliseconds}ms',
            );
            await Future.delayed(wait);
            continue;
          }
          throw const FoodScanException(
            FoodScanErrorType.rateLimited,
            'Food analysis is temporarily busy. Please try again in a moment.',
          );
        }
        if (response.statusCode == 404) {
          debugPrint(
            '[FoodVisionService] configured vision model was not found',
          );
          throw const FoodScanException(
            FoodScanErrorType.api,
            'Food analysis model is unavailable. Please restart the app and try again.',
          );
        }
        // 5xx errors are also worth a short retry — the same transient,
        // provider-side congestion that causes 429s often surfaces as a
        // 503 instead.
        if (response.statusCode >= 500 && response.statusCode < 600) {
          if (attempt < maxAttempts) {
            debugPrint(
              '[FoodVisionService] server error ${response.statusCode} '
              '(attempt $attempt/$maxAttempts) — retrying',
            );
            await Future.delayed(Duration(milliseconds: 700 * attempt));
            continue;
          }
          throw const FoodScanException(
            FoodScanErrorType.api,
            'Food analysis is temporarily unavailable.',
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

    // Unreachable in practice — every branch above either returns or
    // throws — but required so the function has a return path for the
    // analyzer.
    throw const FoodScanException(
      FoodScanErrorType.rateLimited,
      'Food analysis is temporarily busy. Please try again in a moment.',
    );
  }

  Map<String, dynamic> _parseObject(String text) {
    final clean = text
        .replaceAll(
          RegExp(r'<think>[\s\S]*?</think>', caseSensitive: false),
          '',
        )
        .replaceAll(RegExp(r'```(?:json)?', caseSensitive: false), '')
        .replaceAll('```', '')
        .trim();
    final start = clean.indexOf('{');
    final end = clean.lastIndexOf('}');
    if (start < 0 || end <= start) {
      throw const FoodScanException(
        FoodScanErrorType.invalidResponse,
        'Food analysis returned an unreadable result.',
      );
    }
    try {
      return jsonDecode(clean.substring(start, end + 1))
          as Map<String, dynamic>;
    } catch (_) {
      throw const FoodScanException(
        FoodScanErrorType.invalidResponse,
        'Food analysis returned an unreadable result.',
      );
    }
  }
}

class _PreparedImage {
  const _PreparedImage({required this.base64, required this.mimeType});
  final String base64;
  final String mimeType;
}
