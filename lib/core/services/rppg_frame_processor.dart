import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import 'rppg_service.dart';

/// Bridges the `camera` package's raw frame stream and `google_mlkit_face_detection`
/// to produce the [RppgSample] stream [RppgService] needs.
///
/// This is the part most likely to need on-device tweaking — camera image
/// formats differ by platform (YUV420 on Android, BGRA8888 on iOS) and by
/// specific device, so treat the rotation/format handling here as a solid
/// starting point rather than guaranteed-correct for every phone.
class RppgFrameProcessor {
  RppgFrameProcessor()
      : _faceDetector = FaceDetector(
          options: FaceDetectorOptions(
            performanceMode: FaceDetectorMode.fast,
            enableTracking: false,
          ),
        );

  final FaceDetector _faceDetector;
  bool _busy = false;

  /// Call for every frame from `CameraController.startImageStream`.
  /// Returns null while no face is found, a frame is skipped (already busy
  /// processing a previous one), or the frame is otherwise unusable.
  Future<RppgSample?> process(CameraImage image, CameraDescription camera) async {
    if (_busy) return null; // drop frames instead of queueing — keeps up with live video
    _busy = true;
    try {
      final inputImage = _toInputImage(image, camera);
      if (inputImage == null) return null;

      final faces = await _faceDetector.processImage(inputImage);
      if (faces.isEmpty) return null;

      // Largest detected face — most likely the person deliberately framed
      // in shot, rather than someone in the background.
      final face = faces.reduce(
          (a, b) => a.boundingBox.width * a.boundingBox.height >
                  b.boundingBox.width * b.boundingBox.height
              ? a
              : b);

      // Sample the forehead/upper-cheek region rather than the whole face —
      // avoids eyes, mouth movement, and hair, which add noise.
      final box = face.boundingBox;
      final roi = Rect.fromLTWH(
        box.left + box.width * 0.25,
        box.top + box.height * 0.10,
        box.width * 0.5,
        box.height * 0.25,
      );

      return _meanRgbInBox(image, roi);
    } catch (_) {
      return null; // a single bad frame shouldn't crash the scan
    } finally {
      _busy = false;
    }
  }

  Future<void> dispose() => _faceDetector.close();

  InputImage? _toInputImage(CameraImage image, CameraDescription camera) {
    // Assumes the app is locked to portrait (matches VitalsScanScreen).
    final rotationCompensation =
        camera.lensDirection == CameraLensDirection.front
            ? camera.sensorOrientation % 360
            : (camera.sensorOrientation + 360) % 360;
    final rotation =
        InputImageRotationValue.fromRawValue(rotationCompensation) ??
            InputImageRotation.rotation0deg;

    if (Platform.isIOS) {
      if (image.format.group != ImageFormatGroup.bgra8888) return null;
      final plane = image.planes.first;
      return InputImage.fromBytes(
        bytes: plane.bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rotation,
          format: InputImageFormat.bgra8888,
          bytesPerRow: plane.bytesPerRow,
        ),
      );
    }

    // Android: `camera` delivers YUV_420_888 (3 separate, possibly padded
    // planes). ML Kit's Android backend specifically expects NV21, not
    // YUV_420_888 planes concatenated as-is — relying on
    // `image.format.raw` to auto-detect this reliably fails silently on
    // many devices (returns null -> every frame silently dropped -> scan
    // never progresses). Repacking into NV21 by hand avoids that.
    if (image.planes.length < 3) return null;
    final nv21 = _yuv420ToNv21(image);
    return InputImage.fromBytes(
      bytes: nv21,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: InputImageFormat.nv21,
        bytesPerRow: image.width, // no padding after repacking
      ),
    );
  }

  /// Repacks Android's YUV_420_888 (3 planes, possibly with row padding
  /// and interleaved chroma) into NV21 (Y plane, then interleaved V,U).
  Uint8List _yuv420ToNv21(CameraImage image) {
    final width = image.width;
    final height = image.height;
    final yPlane = image.planes[0];
    final uPlane = image.planes[1];
    final vPlane = image.planes[2];

    final nv21 = Uint8List(width * height + (width * height ~/ 2));

    int idY = 0;
    for (int y = 0; y < height; y++) {
      final rowStart = y * yPlane.bytesPerRow;
      for (int x = 0; x < width; x++) {
        nv21[idY++] = yPlane.bytes[rowStart + x];
      }
    }

    final uvWidth = width ~/ 2;
    final uvHeight = height ~/ 2;
    final uRowStride = uPlane.bytesPerRow;
    final uPixelStride = uPlane.bytesPerPixel ?? 1;
    final vRowStride = vPlane.bytesPerRow;
    final vPixelStride = vPlane.bytesPerPixel ?? 1;

    int idUV = width * height;
    for (int y = 0; y < uvHeight; y++) {
      for (int x = 0; x < uvWidth; x++) {
        final uIndex = y * uRowStride + x * uPixelStride;
        final vIndex = y * vRowStride + x * vPixelStride;
        nv21[idUV++] = vPlane.bytes[vIndex]; // NV21 = V then U
        nv21[idUV++] = uPlane.bytes[uIndex];
      }
    }

    return nv21;
  }

  /// Averages R/G/B directly from the camera's raw plane data within [roi],
  /// clipped to the image bounds. Handles YUV420 (Android) and BGRA8888
  /// (iOS) — the two formats `camera` actually delivers.
  RppgSample? _meanRgbInBox(CameraImage image, Rect roi) {
    final left = roi.left.clamp(0, image.width - 1).toInt();
    final top = roi.top.clamp(0, image.height - 1).toInt();
    final right = roi.right.clamp(left + 1, image.width).toInt();
    final bottom = roi.bottom.clamp(top + 1, image.height).toInt();
    if (right <= left || bottom <= top) return null;

    double sumR = 0, sumG = 0, sumB = 0;
    int count = 0;

    if (image.format.group == ImageFormatGroup.bgra8888) {
      final plane = image.planes.first;
      final bytesPerRow = plane.bytesPerRow;
      for (int y = top; y < bottom; y += 2) {
        for (int x = left; x < right; x += 2) {
          final i = y * bytesPerRow + x * 4;
          if (i + 2 >= plane.bytes.length) continue;
          final b = plane.bytes[i];
          final g = plane.bytes[i + 1];
          final r = plane.bytes[i + 2];
          sumR += r;
          sumG += g;
          sumB += b;
          count++;
        }
      }
    } else if (image.format.group == ImageFormatGroup.yuv420) {
      final yPlane = image.planes[0];
      final uPlane = image.planes[1];
      final vPlane = image.planes[2];
      final yRowStride = yPlane.bytesPerRow;
      final uvRowStride = uPlane.bytesPerRow;
      final uvPixelStride = uPlane.bytesPerPixel ?? 1;

      for (int y = top; y < bottom; y += 2) {
        for (int x = left; x < right; x += 2) {
          final yIndex = y * yRowStride + x;
          final uvIndex = (y ~/ 2) * uvRowStride + (x ~/ 2) * uvPixelStride;
          if (yIndex >= yPlane.bytes.length ||
              uvIndex >= uPlane.bytes.length ||
              uvIndex >= vPlane.bytes.length) {
            continue;
          }
          final yVal = yPlane.bytes[yIndex];
          final uVal = uPlane.bytes[uvIndex] - 128;
          final vVal = vPlane.bytes[uvIndex] - 128;

          // Standard YUV -> RGB (BT.601).
          final r = (yVal + 1.402 * vVal).clamp(0, 255);
          final g = (yVal - 0.344136 * uVal - 0.714136 * vVal).clamp(0, 255);
          final b = (yVal + 1.772 * uVal).clamp(0, 255);

          sumR += r;
          sumG += g;
          sumB += b;
          count++;
        }
      }
    } else {
      return null; // unsupported format on this device
    }

    if (count == 0) return null;
    return RppgSample(
      timestampMs: DateTime.now().millisecondsSinceEpoch,
      r: sumR / count,
      g: sumG / count,
      b: sumB / count,
    );
  }
}
