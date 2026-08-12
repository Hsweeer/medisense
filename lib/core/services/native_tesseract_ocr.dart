import 'dart:async';

import 'package:flutter/services.dart';

/// Direct bridge to the real Tesseract OCR engine, via our own native
/// Android plugin (android/app/.../TesseractOcrPlugin.kt), which calls
/// Tesseract4Android's TessBaseAPI — a compiled build of the actual
/// tesseract-ocr/tesseract + tesseract-ocr/leptonica C++ source. No
/// Flutter/Dart OCR package is involved anywhere in this path; this class
/// and its native counterpart together ARE the whole integration.
class NativeTesseractOcr {
  NativeTesseractOcr._();

  static const MethodChannel _channel =
      MethodChannel('com.medisense.medisense_app/tesseract_ocr');

  /// [tessdataParentPath] must be the folder that CONTAINS a "tessdata"
  /// subfolder holding "<language>.traineddata" files — NOT the tessdata
  /// folder itself. This matches TessBaseAPI's own convention on the
  /// native side. Use [LanguagePackManager.tessdataParentDir] for this.
  ///
  /// A hard 60s timeout guards against ever hanging the UI indefinitely —
  /// on a very large/complex image or a weak device this throws a clear
  /// TimeoutException instead of spinning forever with no feedback.
  static Future<String> extractText({
    required String imagePath,
    required String tessdataParentPath,
    required String language,
  }) async {
    final result = await _channel.invokeMethod<String>('extractText', {
      'imagePath': imagePath,
      'tessdataParentPath': tessdataParentPath,
      'language': language,
    }).timeout(
      const Duration(seconds: 60),
      onTimeout: () => throw TimeoutException(
          'OCR took longer than 60s — try a smaller/clearer photo'),
    );
    return result ?? '';
  }
}