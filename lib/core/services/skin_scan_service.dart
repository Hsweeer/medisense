import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

/// One scored skin attribute returned by the server, e.g. "Oiliness: 0.72".
class SkinMetric {
  const SkinMetric({required this.label, required this.score});
  final String label;
  final double score; // 0.0 - 1.0
}

class SkinScanResult {
  const SkinScanResult({required this.metrics, this.overlayImageBase64});
  final List<SkinMetric> metrics;
  /// Optional base64 image (face with markers drawn on it) if the server
  /// returns one — null if not present, in which case the UI just shows
  /// the original photo without markers.
  final String? overlayImageBase64;
}

class SkinScanService {
  SkinScanService._();

  // The skin-scan server deployed on Render (see skin-scan repo).
  // Free-tier Render instances sleep after ~15 min idle, so the first
  // request after a while can take 30-60s to wake the server back up.
  static const String _baseUrl = 'https://skin-scan-j8gj.onrender.com';

  static Future<String> _bakeOrientation(String inputPath) async {
    try {
      final bytes = await File(inputPath).readAsBytes();
      img.Image? image = img.decodeImage(bytes);
      if (image == null) return inputPath; // fall back to original on failure

      // Physically applies whatever EXIF rotation/flip tag is present, then
      // clears the tag — the resulting JPEG is upright with no metadata to
      // ignore.
      image = img.bakeOrientation(image);

      final tempDir = await getTemporaryDirectory();
      final outPath =
          '${tempDir.path}/skin_upload_${DateTime.now().millisecondsSinceEpoch}.jpg';
      await File(outPath).writeAsBytes(img.encodeJpg(image, quality: 92));
      return outPath;
    } catch (_) {
      return inputPath;
    }
  }

  static Future<SkinScanResult> analyze(String imagePath) async {
    // Phones save rotation as EXIF metadata, not by physically rotating the
    // pixels. The Python server reads the raw pixel array and ignores this
    // metadata, so a photo that looks upright on-screen can arrive at the
    // server sideways — causing its face detector to fail even though the
    // photo is genuinely fine. "Baking" the orientation here rotates the
    // actual pixels to match, so what the server reads matches what the
    // person saw when they took the photo.
    final uploadPath = await compute(_bakeOrientation, imagePath);

    final uri = Uri.parse('$_baseUrl/scan');
    final request = http.MultipartRequest('POST', uri);
    request.files.add(await http.MultipartFile.fromPath('image', uploadPath));

    // Long timeout to cover Render's free-tier cold start, not just the
    // analysis itself.
    final streamed = await request.send().timeout(const Duration(seconds: 75));
    final body = await streamed.stream.bytesToString();

    if (streamed.statusCode != 200) {
      throw Exception('Skin scan server error ${streamed.statusCode}: $body');
    }

    final Map<String, dynamic> data = jsonDecode(body);
    return _parse(data);
  }

  /// The server's exact response shape isn't guaranteed field-for-field,
  /// so this reads defensively: any numeric top-level field becomes a
  /// displayed metric, and known non-metric fields are skipped.
  static SkinScanResult _parse(Map<String, dynamic> data) {
    const skipKeys = {
      'image',
      'overlay',
      'overlay_image',
      'annotated_image',
      'filename',
      'success',
      'message',
    };

    final metrics = <SkinMetric>[];

    void addIfNumeric(String key, dynamic value) {
      double? score;
      if (value is num) {
        score = value.toDouble();
      } else if (value is Map && value['score'] is num) {
        score = (value['score'] as num).toDouble();
      }
      if (score != null) {
        metrics.add(SkinMetric(label: _prettyLabel(key), score: score.clamp(0.0, 1.0)));
      }
    }

    data.forEach((key, value) {
      if (skipKeys.contains(key)) return;

      if (value is num) {
        addIfNumeric(key, value);
      } else if (value is Map) {
        // Could be a single {"score": x} shape, or a nested container like
        // {"scores": {"redness": 0.5, "oiliness": 0.05, ...}} — try both.
        if (value['score'] is num) {
          addIfNumeric(key, value);
        } else {
          value.forEach((subKey, subValue) {
            if (subValue is num) addIfNumeric(subKey.toString(), subValue);
          });
        }
      }
    });

    final overlay = (data['overlay_image'] ?? data['annotated_image'] ?? data['overlay'])
    as String?;

    if (metrics.isEmpty) {
      debugPrint('[SkinScanService] No numeric metrics found in response: $data');
    }

    return SkinScanResult(metrics: metrics, overlayImageBase64: overlay);
  }

  static String _prettyLabel(String key) {
    final spaced = key.replaceAll('_', ' ');
    return spaced.isEmpty
        ? key
        : spaced[0].toUpperCase() + spaced.substring(1);
  }
}