import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

/// Owns the on-disk tessdata folder the native TessBaseAPI bridge expects
/// (`<parentDir>/tessdata/eng.traineddata`), and makes sure the app's
/// bundled English language file is copied into it.
///
/// English-only, on purpose — this is the simple baseline. Multi-language
/// support (on-demand downloads, a language picker, "best" vs "fast"
/// model quality) was tried and rolled back; this is the version to build
/// back up from if that's ever revisited.
class LanguagePackManager {
  LanguagePackManager._();
  static final instance = LanguagePackManager._();

  static const _bundledEnglishAsset = 'assets/tessdata/eng.traineddata';

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

  /// Copies the app's bundled eng.traineddata from Flutter assets into the
  /// real runtime tessdata folder, if it isn't there yet. Cheap to call
  /// repeatedly — only does real work once per install.
  Future<void> ensureBundledEnglishReady() async {
    if (_englishReady) return;
    final parent = await tessdataParentDir();
    final dir = Directory('$parent/tessdata');
    await dir.create(recursive: true);
    final engFile = File('${dir.path}/eng.traineddata');
    if (!await engFile.exists()) {
      final bytes = await rootBundle.load(_bundledEnglishAsset);
      await engFile.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
    }
    _englishReady = true;
  }
}