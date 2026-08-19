import 'dart:io';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';

/// Professional image pre-processing for Vision AI.
/// Optimized for Dr. handwriting: Grayscale + Contrast Stretch + Sharpen.
class ImageCleanerService {
  ImageCleanerService._();

  static Future<String?> cleanForVision(String inputPath) async {
    return await compute(_cleanOnIsolate, inputPath);
  }

  static Future<String?> _cleanOnIsolate(String inputPath) async {
    try {
      final bytes = await File(inputPath).readAsBytes();
      img.Image? image = img.decodeImage(bytes);
      if (image == null) return null;

      // 1. Grayscale
      image = img.grayscale(image);

      // 2. Contrast Stretch (Auto-Level)
      // Professional: Normalize pixel range to 0-255
      image = img.contrast(image, contrast: 1.2); 

      // 3. Mild Sharpen
      // This helps faint pen strokes stand out. We use a simple 3x3 convolution
      // kernel or the built-in convolution for sharpening.
      image = img.convolution(image, filter: [
        0, -1,  0,
       -1,  5, -1,
        0, -1,  0
      ]);

      /*
       NOTE: We do NOT add binarization/thresholding (converting to pure black & white).
       Handwriting often contains faint, variable-pressure strokes that are 
       lost if we threshold too aggressively. Advanced vision models like 
       Gemini perform much better on grayscale/original detail where they 
       can perceive these pressure variations.
      */

      // 4. Save to permanent documents folder under a dedicated subfolder
      final docDir = await getApplicationDocumentsDirectory();
      final photosDir = Directory('${docDir.path}/prescription_photos');
      if (!await photosDir.exists()) {
        await photosDir.create(recursive: true);
      }
      
      final outputPath = '${photosDir.path}/cleaned_${DateTime.now().millisecondsSinceEpoch}.jpg';
      
      await File(outputPath).writeAsBytes(img.encodeJpg(image, quality: 90));
      
      debugPrint('[ImageCleaner] Processed and saved to permanent storage: $outputPath');
      return outputPath;
    } catch (e) {
      debugPrint('[ImageCleaner] Error: $e');
      return null;
    }
  }
}
