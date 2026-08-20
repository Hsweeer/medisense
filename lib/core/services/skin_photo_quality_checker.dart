import 'dart:io';

import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

enum SkinPhotoQuality { ok, noFace, multipleFaces, faceTooTilted }

/// Checks a still photo (not live camera) has exactly one clear,
/// front-facing face before it's sent for skin analysis — a scan of a
/// blurry, sideways, or group photo gives meaningless results.
class SkinPhotoQualityChecker {
  SkinPhotoQualityChecker._();

  static final _detector = FaceDetector(
    options: FaceDetectorOptions(
      performanceMode: FaceDetectorMode.accurate,
      enableTracking: false,
    ),
  );

  static Future<SkinPhotoQuality> check(String imagePath) async {
    try {
      final inputImage = InputImage.fromFile(File(imagePath));
      final faces = await _detector.processImage(inputImage);

      if (faces.isEmpty) return SkinPhotoQuality.noFace;
      if (faces.length > 1) return SkinPhotoQuality.multipleFaces;

      final face = faces.first;
      // headEulerAngleY = left/right turn, headEulerAngleZ = tilt.
      final yaw = face.headEulerAngleY?.abs() ?? 0;
      final roll = face.headEulerAngleZ?.abs() ?? 0;
      if (yaw > 25 || roll > 25) return SkinPhotoQuality.faceTooTilted;

      return SkinPhotoQuality.ok;
    } catch (_) {
      // On-device detector failure shouldn't block the whole feature —
      // let the server-side analysis be the final say.
      return SkinPhotoQuality.ok;
    }
  }

  static String message(SkinPhotoQuality q) {
    switch (q) {
      case SkinPhotoQuality.noFace:
        return "MedAI couldn't find a face in that photo. Try again with your face clearly visible.";
      case SkinPhotoQuality.multipleFaces:
        return "MedAI found more than one face. Please scan a photo with just your face.";
      case SkinPhotoQuality.faceTooTilted:
        return "Face the camera directly for an accurate scan.";
      case SkinPhotoQuality.ok:
        return '';
    }
  }
}