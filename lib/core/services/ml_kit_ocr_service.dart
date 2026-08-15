import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:flutter/foundation.dart';

/// Professional-grade OCR using Google ML Kit.
/// Handles handwriting and natural scenes significantly better than Tesseract.
class MLKitOCRService {
  MLKitOCRService._();

  static final _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);

  static Future<String> extractText(String imagePath) async {
    try {
      final inputImage = InputImage.fromFilePath(imagePath);
      final RecognizedText recognizedText = await _textRecognizer.processImage(inputImage);

      // Professional Apps don't just return raw text; 
      // they clean up line breaks and common doctor notation errors.
      String result = recognizedText.text;
      
      // Clean up common noise
      result = result.replaceAll('|', 'I'); // OCR often mistakes 'I' for '|'
      
      debugPrint('[MLKitOCR] Extracted text: ${result.length} characters');
      return result;
    } catch (e) {
      debugPrint('[MLKitOCR] Error: $e');
      return '';
    }
  }

  static void dispose() {
    _textRecognizer.close();
  }
}
