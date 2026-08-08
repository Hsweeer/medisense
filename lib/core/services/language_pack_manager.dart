import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Downloads and tracks Tesseract OCR language packs, and owns the on-disk
/// folder layout the native TessBaseAPI bridge expects
/// (`<parentDir>/tessdata/<code>.traineddata`).
///
/// English ships bundled inside the app (assets/tessdata/eng.traineddata)
/// and is copied into place on first use — no network call needed. Every
/// other language is fetched once — directly from the official Tesseract
/// project's public model repository, not from any server of ours — the
/// first time it's selected, then cached on-device permanently. No
/// language is ever re-downloaded once it's on-device.
class LanguagePackManager {
  LanguagePackManager._();
  static final instance = LanguagePackManager._();

  static const _activeLangKey = 'ocr_active_language';
  static const _fastSourceBase =
      'https://raw.githubusercontent.com/tesseract-ocr/tessdata_fast/main';
  static const _bestSourceBase =
      'https://github.com/tesseract-ocr/tessdata_best/raw/main';
  static const _bundledEnglishAsset = 'assets/tessdata/eng.traineddata';

  /// Languages downloaded from the larger, higher-accuracy `tessdata` repo
  /// instead of `tessdata_fast`. Chosen because these are the complex,
  /// dense-character scripts where Tesseract's fast/compressed models are
  /// historically noticeably weaker (measured: Japanese jumps from ~2.4MB
  /// to ~34.8MB between fast→best — a real model-capacity difference, not
  /// just compression). Everything else stays on `fast`: for most
  /// Latin-alphabet and simpler-script languages the accuracy gap is
  /// small and not worth 5-15x the download size.
  static const Set<String> _preferBestQuality = {
    'jpn', 'jpn_vert', // Japanese
    'chi_sim', 'chi_sim_vert', 'chi_tra', 'chi_tra_vert', // Chinese
    'kor', 'kor_vert', // Korean
    'tha', // Thai
    'mya', // Burmese
    'khm', // Khmer
    'bod', // Tibetan
  };

  bool prefersBestQuality(String code) => _preferBestQuality.contains(code);

  String? _cachedParentDir;
  bool _englishReady = false;

  /// The folder that CONTAINS the "tessdata" subfolder — this is what
  /// gets passed to TessBaseAPI.init() on the native side, per its own
  /// convention (it appends "/tessdata/<lang>.traineddata" itself).
  Future<String> tessdataParentDir() async {
    if (_cachedParentDir != null) return _cachedParentDir!;
    final support = await getApplicationSupportDirectory();
    final parent = '${support.path}/tesseract';
    _cachedParentDir = parent;
    return parent;
  }

  Future<Directory> _tessdataDir() async {
    final parent = await tessdataParentDir();
    final dir = Directory('$parent/tessdata');
    await dir.create(recursive: true);
    return dir;
  }

  /// Copies the app's bundled eng.traineddata from Flutter assets into the
  /// real runtime tessdata folder, if it isn't there yet. Cheap to call
  /// repeatedly — only does real work once per install.
  Future<void> ensureBundledEnglishReady() async {
    if (_englishReady) return;
    final dir = await _tessdataDir();
    final engFile = File('${dir.path}/eng.traineddata');
    if (!await engFile.exists()) {
      final bytes = await rootBundle.load(_bundledEnglishAsset);
      await engFile.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
    }
    _englishReady = true;
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
    if (code == 'eng') return true; // always installable from bundled assets
    final dir = await _tessdataDir();
    return File('${dir.path}/$code.traineddata').exists();
  }

  /// Downloads one language pack, reporting progress from 0.0 to 1.0.
  /// Throws on failure (no internet, 404, interrupted connection, etc.) —
  /// the caller shows that to the user. Writes to a temporary ".part" file
  /// first and only renames it into place once the full download
  /// succeeds, so an interrupted download can never leave a corrupt,
  /// half-written language file that would silently break OCR.
  Future<void> download(
    String code, {
    void Function(double progress)? onProgress,
  }) async {
    final dir = await _tessdataDir();

    final base = _preferBestQuality.contains(code) ? _bestSourceBase : _fastSourceBase;
    final uri = Uri.parse('$base/$code.traineddata');
    final client = http.Client();
    try {
      final response = await client
          .send(http.Request('GET', uri))
          .timeout(const Duration(seconds: 60));

      if (response.statusCode != 200) {
        throw Exception(
            'Could not download this language pack (HTTP ${response.statusCode}).');
      }

      final total = response.contentLength ?? 0;
      var received = 0;
      final tempFile = File('${dir.path}/$code.traineddata.part');
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
      await tempFile.rename('${dir.path}/$code.traineddata');
    } finally {
      client.close();
    }
  }

  /// Frees storage by removing a downloaded language pack. English can't
  /// be removed — it's the app's built-in default and needs to always
  /// work with zero setup.
  Future<void> delete(String code) async {
    if (code == 'eng') return;
    final dir = await _tessdataDir();
    final file = File('${dir.path}/$code.traineddata');
    if (await file.exists()) await file.delete();
    if (await activeLanguage() == code) await setActiveLanguage('eng');
  }
}