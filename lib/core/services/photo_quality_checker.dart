import 'dart:io';
import 'dart:math';
import 'package:image/image.dart' as img;
import 'package:flutter/foundation.dart';

enum QualityResult { ok, tooDark, tooBlurry, tooSmall }

class PhotoQualityChecker {
  PhotoQualityChecker._();

  /// Basic thresholds - these will be tuned after real-world testing.
  static const int minDimension = 500;
  static const double minBrightness = 40.0; // 0-255 scale
  static const double minVariance = 100.0;  // Variance of brightness

  static Future<QualityResult> check(String imagePath) async {
    return await compute(_checkOnIsolate, imagePath);
  }

  static Future<QualityResult> _checkOnIsolate(String path) async {
    try {
      final bytes = await File(path).readAsBytes();
      final image = img.decodeImage(bytes);
      if (image == null) return QualityResult.tooBlurry;

      // 1. Check Dimensions
      if (image.width < minDimension || image.height < minDimension) {
        return QualityResult.tooSmall;
      }

      // 2. Sample pixels for Brightness and Variance
      // We sample a grid to keep it fast even for large images.
      double sum = 0;
      double sumSq = 0;
      int count = 0;

      final stepX = max(1, image.width ~/ 20);
      final stepY = max(1, image.height ~/ 20);

      for (int y = 0; y < image.height; y += stepY) {
        for (int x = 0; x < image.width; x += stepX) {
          final pixel = image.getPixel(x, y);
          // Convert to grayscale brightness (Luma)
          final luma = 0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b;
          
          sum += luma;
          sumSq += luma * luma;
          count++;
        }
      }

      if (count == 0) return QualityResult.tooDark;

      final avgBrightness = sum / count;
      final variance = (sumSq / count) - (avgBrightness * avgBrightness);

      debugPrint('[QualityCheck] Avg Brightness: ${avgBrightness.toStringAsFixed(1)} (min: $minBrightness)');
      debugPrint('[QualityCheck] Variance: ${variance.toStringAsFixed(1)} (min: $minVariance)');

      if (avgBrightness < minBrightness) {
        return QualityResult.tooDark;
      }

      if (variance < minVariance) {
        return QualityResult.tooBlurry;
      }

      return QualityResult.ok;
    } catch (e) {
      debugPrint('[QualityCheck] Error: $e');
      return QualityResult.ok; // Default to OK on technical failure
    }
  }
}
