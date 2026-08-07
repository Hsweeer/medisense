import 'dart:io';

import 'package:flutter_tesseract_ocr/flutter_tesseract_ocr.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Downloads and tracks additional Tesseract OCR language packs on demand.
///
/// English ships bundled inside the app (assets/tessdata/eng.traineddata)
/// and is always available offline, from install, with zero network calls.
/// Every other language is fetched once — directly from the official
/// Tesseract project's public model repository, not from any server of
/// ours — the first time it's selected, then written into the same
/// tessdata folder the OCR engine already reads from
/// ([FlutterTesseractOcr.getTessdataPath]) and cached there permanently.
/// No language is ever re-downloaded once it's on-device.
class LanguagePackManager {
  LanguagePackManager._();
  static final instance = LanguagePackManager._();

  static const _activeLangKey = 'ocr_active_language';
  static const _sourceBase =
      'https://raw.githubusercontent.com/tesseract-ocr/tessdata_fast/main';

  String? _cachedDir;

  Future<String> _tessdataDir() async {
    return _cachedDir ??= await FlutterTesseractOcr.getTessdataPath();
  }

  /// The language code OCR should currently use — "eng" until the user
  /// picks something else.
  Future<String> activeLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_activeLangKey) ?? 'eng';
  }

  Future<void> setActiveLanguage(String code) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_activeLangKey, code);
  }

  Future<bool> isInstalled(String code) async {
    if (code == 'eng') return true; // bundled with the app itself
    final dir = await _tessdataDir();
    return File('$dir/$code.traineddata').exists();
  }

  /// Downloads one language pack, reporting progress from 0.0 to 1.0.
  /// Throws on failure (no internet, 404, interrupted connection, etc.) —
  /// the caller is responsible for showing that to the user. Writes to a
  /// temporary ".part" file first and only renames it into place once the
  /// full download succeeds, so an interrupted download can never leave a
  /// corrupt, half-written language file that would silently break OCR.
  Future<void> download(
    String code, {
    void Function(double progress)? onProgress,
  }) async {
    final dir = await _tessdataDir();
    await Directory(dir).create(recursive: true);

    final uri = Uri.parse('$_sourceBase/$code.traineddata');
    final client = http.Client();
    try {
      final response = await client
          .send(http.Request('GET', uri))
          .timeout(const Duration(seconds: 40));

      if (response.statusCode != 200) {
        throw Exception(
            'Could not download this language pack (HTTP ${response.statusCode}).');
      }

      final total = response.contentLength ?? 0;
      var received = 0;
      final tempFile = File('$dir/$code.traineddata.part');
      final sink = tempFile.openWrite();
      try {
        await for (final chunk in response.stream) {
          sink.add(chunk);
          received += chunk.length;
          if (total > 0) onProgress?.call(received / total);
        }
        await sink.flush();
      } finally {
        await sink.close();
      }
      await tempFile.rename('$dir/$code.traineddata');
    } finally {
      client.close();
    }
  }

  /// Frees storage by removing a downloaded language pack. English can't
  /// be removed — it's the app's built-in default and needs to always work
  /// with zero setup.
  Future<void> delete(String code) async {
    if (code == 'eng') return;
    final dir = await _tessdataDir();
    final file = File('$dir/$code.traineddata');
    if (await file.exists()) await file.delete();
    if (await activeLanguage() == code) await setActiveLanguage('eng');
  }
}