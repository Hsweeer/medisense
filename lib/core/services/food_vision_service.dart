// lib/core/services/food_vision_service.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

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

  // Serializes every request through this service (vision AND text) so
  // two scans fired close together — e.g. the user tapping "Try again"
  // right after a failed attempt, or a quick double-tap on the shutter —
  // never hit Groq at the same moment. Two requests colliding is exactly
  // what turns one transient 429 into two, competing for the same
  // already-scarce vision "preview" quota. Queuing them one after the
  // other instead means the second one benefits from whatever backoff
  // the first one already did, rather than adding fresh pressure.
  Future<void> _queue = Future.value();

  Future<T> _serialized<T>(Future<T> Function() task) {
    final previous = _queue;
    final completer = Completer<void>();
    _queue = completer.future;
    return previous.then((_) => task()).whenComplete(completer.complete);
  }

  // Text-only requests (estimateNutrition — no image involved) don't need
  // the vision-capable model at all. Routing them there anyway meant
  // every single scan made TWO calls against the same tightly rate-
  // limited "preview" vision quota instead of one, roughly doubling how
  // often that quota got exhausted for no benefit. This reuses the same
  // production text model GroqService already relies on successfully
  // elsewhere in the app (MedAI chat) — a separate, much higher-quota
  // pool, so nutrition estimation no longer competes with photo
  // identification for the same scarce vision-model rate limit.
  static const _textModel = 'openai/gpt-oss-20b';

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
    final content = await _request(
      [
        {
          'type': 'text',
          'text':
              'Estimate nutrition for "${food.foodName}", portion: ${food.estimatedPortion}'
              '${food.estimatedWeightGrams != null ? ' (~${food.estimatedWeightGrams!.round()}g)' : ''}. '
              'Return ONLY JSON with calories (number), carbsG (number), fatG (number), '
              'proteinG (number), dietaryStatus ("halal", "haram", or "unknown"), and '
              'portionLabel (string). Do not use markdown.',
        },
      ],
      // No image in this request — use the production text model instead
      // of the scarce vision-only one (see _textModel above).
      modelOverride: _textModel,
    );
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

  /// Groq reports rate-limit reset times using a Go-style duration
  /// string — e.g. "7.66s", "1m2s", "500ms" — not a plain integer. The
  /// previous code only ever tried `int.tryParse()` on this, which
  /// silently returns null for every one of those formats. That meant
  /// the client NEVER actually used Groq's own precise "wait exactly
  /// this long" value, even when Groq provided it — it always fell back
  /// to a blind exponential guess, which is exactly why scans were
  /// bouncing through 5-6 rate-limited attempts instead of succeeding
  /// right after a single correctly-sized wait.
  Duration? _parseGroqResetDuration(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final trimmed = value.trim();

    // Plain integer seconds (some responses/proxies use this form).
    final plainSeconds = int.tryParse(trimmed);
    if (plainSeconds != null) return Duration(seconds: plainSeconds);

    final match = RegExp(
      r'^(?:(\d+)m)?(?:([\d.]+)s)?(?:(\d+)ms)?$',
    ).firstMatch(trimmed);
    if (match == null) return null;

    final minutes = int.tryParse(match.group(1) ?? '') ?? 0;
    final secondsPart = double.tryParse(match.group(2) ?? '') ?? 0;
    final millisPart = int.tryParse(match.group(3) ?? '') ?? 0;
    final totalMs =
        (minutes * 60000) + (secondsPart * 1000).round() + millisPart;

    return totalMs > 0 ? Duration(milliseconds: totalMs) : null;
  }

  /// Reads whichever of Groq's rate-limit headers is present and
  /// meaningful, preferring the token-bucket reset time specifically
  /// (this app's limit is token-volume based, not request-count based),
  /// then falling back to Retry-After, then the request-count reset.
  Duration? _serverReportedWait(http.Response response) {
    final tokenReset = _parseGroqResetDuration(
      response.headers['x-ratelimit-reset-tokens'],
    );
    if (tokenReset != null) return tokenReset;

    final retryAfter = _parseGroqResetDuration(response.headers['retry-after']);
    if (retryAfter != null) return retryAfter;

    return _parseGroqResetDuration(
      response.headers['x-ratelimit-reset-requests'],
    );
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
    // Vision-model token cost scales with image resolution, and Groq's
    // free-tier for this model caps out at just 8,000 tokens/minute (see
    // the retry comments above) — a 1600px-wide image was eating a large
    // enough share of that budget that even one or two scans in the same
    // minute could exhaust it, and once exhausted, no amount of client-
    // side retrying helps until the next 60-second window rolls over.
    // 1024px is still comfortably enough resolution for a phone photo of
    // a plate of food to be recognized correctly, while meaningfully
    // cutting the tokens each request actually costs — the real lever
    // here, since the limit is per-minute token volume, not request
    // count.
    final resized = decoded.width > 1024
        ? image_lib.copyResize(decoded, width: 1024)
        : decoded;
    return _PreparedImage(
      base64: base64Encode(
        Uint8List.fromList(image_lib.encodeJpg(resized, quality: 80)),
      ),
      mimeType: 'image/jpeg',
    );
  }

  /// Public entry point every caller uses — queues through [_serialized]
  /// so overlapping scans don't compete for the same tight quota.
  Future<String> _request(
    List<Map<String, dynamic>> content, {
    String? modelOverride,
  }) {
    return _serialized(
      () => _requestUnserialized(content, modelOverride: modelOverride),
    );
  }

  Future<String> _requestUnserialized(
    List<Map<String, dynamic>> content, {
    String? modelOverride,
  }) async {
    final apiKey = dotenv.env['GROQ_API_KEY']?.trim() ?? '';
    if (apiKey.isEmpty) {
      throw const FoodScanException(
        FoodScanErrorType.authentication,
        'Food analysis is not configured.',
      );
    }

    final model = modelOverride ?? _model;

    // qwen/qwen3.6-27b is currently served by Groq as a "preview" model
    // (their only vision-capable option after retiring the Llama vision
    // preview models), which carries much tighter rate limits than their
    // production models. A 429 here is frequently transient — a few
    // short, backed-off retries clears most of them without the user ever
    // seeing an error. Jitter is added to each wait so that if several
    // requests get rate-limited around the same moment (e.g. a burst of
    // scans), their retries don't all land on the exact same millisecond
    // and immediately collide again. 6 attempts with an exponential (not
    // just linear) backoff, capped at 5s per wait, gives the tight
    // preview quota meaningfully more time to free up than the previous
    // 4-attempt/~5s-total budget did, while still resolving well within
    // what someone will patiently wait for on a loading screen.
    const maxAttempts = 6;
    const maxBackoff = Duration(seconds: 5);
    final random = Random();
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
                'model': model,
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
            // Prefer Groq's own precise reset-time headers when present
            // — this is the actual fix: previously this always fell
            // through to the blind exponential guess because the old
            // parser couldn't read Groq's "7.66s"-style duration format.
            // Capped at 20s so a single wait step never feels like the
            // app has frozen, even if the real reset window is longer.
            final serverWait = _serverReportedWait(response);
            final jitter = Duration(milliseconds: random.nextInt(300));
            final exponential = Duration(
              milliseconds: min(
                600 * pow(2, attempt - 1).toInt(),
                maxBackoff.inMilliseconds,
              ),
            );
            final wait = serverWait != null
                ? Duration(
                        milliseconds: min(
                          serverWait.inMilliseconds,
                          const Duration(seconds: 20).inMilliseconds,
                        ),
                      ) +
                      jitter
                : exponential + jitter;
            debugPrint(
              '[FoodVisionService] rate limited (attempt $attempt/$maxAttempts) '
              '— ${serverWait != null ? "Groq reported" : "guessing"} '
              '${wait.inMilliseconds}ms',
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
            final jitter = Duration(milliseconds: random.nextInt(300));
            final wait =
                Duration(
                  milliseconds: min(
                    600 * pow(2, attempt - 1).toInt(),
                    maxBackoff.inMilliseconds,
                  ),
                ) +
                jitter;
            debugPrint(
              '[FoodVisionService] server error ${response.statusCode} '
              '(attempt $attempt/$maxAttempts) — retrying in ${wait.inMilliseconds}ms',
            );
            await Future.delayed(wait);
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
