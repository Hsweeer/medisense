import 'dart:io';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

/// Direct bridge to the real Tesseract OCR engine, via our own native
/// Android plugin (android/app/.../TesseractOcrPlugin.kt), which calls
/// Tesseract4Android's TessBaseAPI — a compiled build of the actual
/// tesseract-ocr/tesseract + tesseract-ocr/leptonica C++ source. No
/// Flutter/Dart OCR package is involved anywhere in this path; this class
/// and its native counterpart together ARE the whole integration.
///
/// Before handing a photo to Tesseract we bake in EXIF orientation,
/// upscale small text, and boost contrast — a raw phone photo of a
/// prescription is usually rotated, low-contrast, and too small for
/// Tesseract to read reliably as-is. That prep work is genuinely CPU-heavy
/// (resizing/recoloring/encoding a multi-megapixel photo), so it runs on a
/// background isolate via [compute] — doing it on the UI isolate is what
/// was freezing the app and triggering "MediSense isn't responding".
///
/// We first try a single sparse-text pass (fast, and correct for most
/// prescription photos and labels). Only if that pass doesn't look like
/// real text do we pay for a second, single-block pass and pick whichever
/// scores better — so a clean scan stays fast, and only a genuinely hard
/// photo pays for both attempts.
class NativeTesseractOcr {
  NativeTesseractOcr._();

  static const MethodChannel _channel =
      MethodChannel('com.medisense.medisense_app/tesseract_ocr');

  static const int _psmSparseText = 11;
  static const int _psmSingleBlock = 6;

  /// A result at/above this score already looks like solid real text — not
  /// worth spending a second full OCR pass trying to beat it.
  static const double _goodEnoughScore = 80;

  /// Below this, a result is more likely noise (stray strokes read as
  /// isolated "i"/"l"/"Il" characters) than real content, so we report "no
  /// text found" instead of showing the user garbage.
  static const double _minReadableScore = 20;

  /// [tessdataParentPath] must be the folder that CONTAINS a "tessdata"
  /// subfolder holding "<language>.traineddata" files — NOT the tessdata
  /// folder itself. This matches TessBaseAPI's own convention on the
  /// native side. Use [LanguagePackManager.tessdataParentDir] for this.
  static Future<String> extractText({
    required String imagePath,
    required String tessdataParentPath,
    required String language,
  }) async {
    final prepared = await _prepareImage(imagePath);
    try {
      final sparse = await _extract(
        prepared.path,
        tessdataParentPath,
        language,
        _psmSparseText,
      );
      final sparseScore = _qualityScore(sparse);

      String best = sparse;
      double bestScore = sparseScore;

      if (sparseScore < _goodEnoughScore) {
        final block = await _extract(
          prepared.path,
          tessdataParentPath,
          language,
          _psmSingleBlock,
        );
        final blockScore = _qualityScore(block);
        if (blockScore > bestScore) {
          best = block;
          bestScore = blockScore;
        }
      }

      return bestScore >= _minReadableScore ? best : '';
    } finally {
      if (prepared.isTemporary && await prepared.file.exists()) {
        await prepared.file.delete();
      }
    }
  }

  static Future<String> _extract(
    String imagePath,
    String tessdataParentPath,
    String language,
    int psm,
  ) async {
    final result = await _channel.invokeMethod<String>('extractText', {
      'imagePath': imagePath,
      'tessdataParentPath': tessdataParentPath,
      'language': language,
      'psm': psm,
    });
    return (result ?? '').trim();
  }

  /// Bakes EXIF rotation, enlarges small text, and increases contrast — the
  /// same prep a dedicated document-scanner app does before running OCR.
  /// Runs on a background isolate (see [_IsolateImagePrepArgs]) so a large
  /// photo can't freeze the UI while it's being prepared.
  static Future<_PreparedOcrImage> _prepareImage(String sourcePath) async {
    try {
      // getTemporaryDirectory() needs the plugin channel, which only works
      // on the main isolate — resolve the output path here, then hand the
      // actual (plugin-free) image work off to compute().
      final tempDir = await getTemporaryDirectory();
      final outputPath = '${tempDir.path}${Platform.pathSeparator}'
          'ocr_${DateTime.now().microsecondsSinceEpoch}.jpg';

      final resultPath = await compute(
        _prepareImageInBackground,
        _IsolateImagePrepArgs(sourcePath, outputPath),
      );

      if (resultPath == null) return _PreparedOcrImage(File(sourcePath), false);
      return _PreparedOcrImage(File(resultPath), true);
    } catch (_) {
      // If preprocessing fails for any reason, fall back to the original
      // photo rather than losing the scan entirely.
      return _PreparedOcrImage(File(sourcePath), false);
    }
  }

  /// Scores words and letters while penalising symbol/noise runs AND
  /// isolated 1–2 letter fragments (the "i | l Il hl" pattern a bad
  /// binarization/handwriting pass produces), so a real block of text
  /// outscores a near-empty or garbled result instead of losing to it.
  static double _qualityScore(String text) {
    final words = RegExp(r'[A-Za-z]{3,}').allMatches(text).length;
    final letters = RegExp(r'[A-Za-z]').allMatches(text).length;
    final shortFragments =
        RegExp(r'(?<![A-Za-z])[A-Za-z]{1,2}(?![A-Za-z])').allMatches(text).length;
    final noise = RegExp(r"[^A-Za-z0-9\s.,;:!?'-]").allMatches(text).length;
    return (words * 14) + (letters * 0.2) - (noise * 8) - (shortFragments * 4);
  }
}

/// Plain data holder passed into [compute] — must be a simple value type
/// since it crosses an isolate boundary.
class _IsolateImagePrepArgs {
  const _IsolateImagePrepArgs(this.sourcePath, this.outputPath);
  final String sourcePath;
  final String outputPath;
}

/// Runs on a background isolate spawned by [compute]. Deliberately uses
/// only dart:io + the `image` package (no plugin/platform-channel calls,
/// which background isolates can't make) — this is the actual CPU-heavy
/// work: decode, bake orientation, resize, grayscale, boost contrast,
/// re-encode. Returns the prepared file's path, or null if the source
/// couldn't be decoded.
String? _prepareImageInBackground(_IsolateImagePrepArgs args) {
  final bytes = File(args.sourcePath).readAsBytesSync();
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;

  final upright = img.bakeOrientation(decoded);
  const minWidth = 1600;
  const maxWidth = 2200;
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

  File(args.outputPath).writeAsBytesSync(img.encodeJpg(enhanced, quality: 96));
  return args.outputPath;
}

class _PreparedOcrImage {
  const _PreparedOcrImage(this.file, this.isTemporary);

  final File file;
  final bool isTemporary;

  String get path => file.path;
}