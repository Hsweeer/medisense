import 'dart:io';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';

/// Professional image pre-processing for Vision AI.
/// Optimized for Dr. handwriting: Grayscale + Contrast Stretch.
/// NO binarization (thresholding) to avoid losing pen pressure details.
class ImageCleanerService {
  ImageCleanerService._();

  static Future<String?> cleanForVision(String inputPath) async {
    try {
      final bytes = await File(inputPath).readAsBytes();
      img.Image? image = img.decodeImage(bytes);
      if (image == null) return null;

      // 1. Grayscale
      image = img.grayscale(image);

      // 2. Contrast Stretch (Auto-Level)
      // Professional: Normalize pixel range to 0-255
      image = img.contrast(image, contrast: 1.2); 

      // 3. Save to temp folder
      final tempDir = await getTemporaryDirectory();
      final outputPath = '${tempDir.path}/cleaned_${DateTime.now().millisecondsSinceEpoch}.jpg';
      
      await File(outputPath).writeAsBytes(img.encodeJpg(image, quality: 90));
      
      debugPrint('[ImageCleaner] Processed: $outputPath');
      return outputPath;
    } catch (e) {
      debugPrint('[ImageCleaner] Error: $e');
      return null;
    }
  }
}
