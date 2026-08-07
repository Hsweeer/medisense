import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_tesseract_ocr/flutter_tesseract_ocr.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

/// Prepares a phone photo for Tesseract before extracting text.
///
/// Phone photos often contain EXIF rotation, shadows, glare, and small text.
/// Tesseract handles them substantially better after orientation is baked,
/// the image is enlarged, and contrast is increased. We run two appropriate
/// page-layout modes and return the more text-like result.
class TesseractOcrService {
  TesseractOcrService._();

  static const _englishModelAsset = 'assets/tessdata/eng.traineddata';
  static const _highAccuracyEnglishModelSize = 15400601;

  static Future<String> extractText(
    String imagePath, {
    required String language,
  }) async {
    await _ensureHighAccuracyEnglishModel(language);
    final prepared = await _prepareImage(imagePath);
    try {
      final sparseText = await _extract(prepared.path, language, psm: '11');
      final blockText = await _extract(prepared.path, language, psm: '6');
      return _qualityScore(blockText) > _qualityScore(sparseText)
          ? blockText.trim()
          : sparseText.trim();
    } finally {
      if (prepared.isTemporary && await prepared.file.exists()) {
        await prepared.file.delete();
      }
    }
  }

  /// The plugin only copies a bundled model when the device has no model file.
  /// Refresh the old cached fast model after an app update so existing users
  /// receive the higher-accuracy English model too.
  static Future<void> _ensureHighAccuracyEnglishModel(String language) async {
    if (language != 'eng') return;

    final tessdataPath = await FlutterTesseractOcr.getTessdataPath();
    final target = File('$tessdataPath${Platform.pathSeparator}eng.traineddata');
    if (await target.exists() &&
        await target.length() == _highAccuracyEnglishModelSize) {
      return;
    }

    await target.parent.create(recursive: true);
    final assetData = await rootBundle.load(_englishModelAsset);
    final replacement = File('${target.path}.updating');
    await replacement.writeAsBytes(
      assetData.buffer.asUint8List(assetData.offsetInBytes, assetData.lengthInBytes),
      flush: true,
    );
    if (await target.exists()) await target.delete();
    await replacement.rename(target.path);
  }

  static Future<String> _extract(
    String imagePath,
    String language, {
    required String psm,
  }) {
    return FlutterTesseractOcr.extractText(
      imagePath,
      language: language,
      args: {
        // 11 handles sparse text on covers and labels; 6 handles document-like
        // blocks. Both are tried above instead of assuming a single column.
        'psm': psm,
        'user_defined_dpi': '300',
        'preserve_interword_spaces': '1',
      },
    );
  }

  static Future<_PreparedOcrImage> _prepareImage(String sourcePath) async {
    final sourceFile = File(sourcePath);
    final bytes = await sourceFile.readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return _PreparedOcrImage(sourceFile, false);

    final upright = img.bakeOrientation(decoded);
    const minWidth = 1600;
    const maxWidth = 2400;
    final targetWidth = upright.width < minWidth
        ? minWidth
        : upright.width > maxWidth
            ? maxWidth
            : upright.width;
    final resized = targetWidth == upright.width
        ? upright
        : img.copyResize(
            upright,
            width: targetWidth,
            interpolation: img.Interpolation.cubic,
          );
    final enhanced = img.adjustColor(
      img.grayscale(resized),
      contrast: 1.55,
      brightness: 1.05,
    );

    final tempDir = await getTemporaryDirectory();
    final output = File(
      '${tempDir.path}${Platform.pathSeparator}'
      'ocr_${DateTime.now().microsecondsSinceEpoch}.jpg',
    );
    await output.writeAsBytes(img.encodeJpg(enhanced, quality: 96), flush: true);
    return _PreparedOcrImage(output, true);
  }

  /// Scores words and letters while penalising URLs/symbol noise, letting a
  /// normal document pass beat a spurious scan of browser/UI text.
  static double _qualityScore(String text) {
    final letters = RegExp(r'[A-Za-z]').allMatches(text).length;
    final words = RegExp(r'[A-Za-z]{2,}').allMatches(text).length;
    final noise = RegExp(r"[^A-Za-z0-9\s.,;:!?'-]").allMatches(text).length;
    return (words * 12) + (letters * 0.3) - (noise * 8);
  }
}

class _PreparedOcrImage {
  const _PreparedOcrImage(this.file, this.isTemporary);

  final File file;
  final bool isTemporary;

  String get path => file.path;
}
