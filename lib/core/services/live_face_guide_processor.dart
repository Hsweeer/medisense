import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

enum LiveFaceGuideStatus { noFace, tooFarOrTilted, good }

/// Bridges the `camera` package's live preview frames and
/// `google_mlkit_face_detection` to give real-time face-positioning
/// feedback while the skin-scan camera is open — same conversion approach
/// as [RppgFrameProcessor] (see that file for why NV21 repacking on
/// Android is necessary), but only needs a quality status per frame, not
/// pixel sampling.
class LiveFaceGuideProcessor {
  LiveFaceGuideProcessor()
      : _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      performanceMode: FaceDetectorMode.fast,
      enableTracking: false,
    ),
  );

  final FaceDetector _faceDetector;
  bool _busy = false;

  Future<LiveFaceGuideStatus?> process(
      CameraImage image, CameraDescription camera) async {
    if (_busy) return null; // drop frames instead of queueing
    _busy = true;
    try {
      final inputImage = _toInputImage(image, camera);
      if (inputImage == null) return null;

      final faces = await _faceDetector.processImage(inputImage);
      if (faces.isEmpty) return LiveFaceGuideStatus.noFace;

      final face = faces.reduce(
              (a, b) => a.boundingBox.width * a.boundingBox.height >
              b.boundingBox.width * b.boundingBox.height
              ? a
              : b);

      final yaw = face.headEulerAngleY?.abs() ?? 0;
      final roll = face.headEulerAngleZ?.abs() ?? 0;
      // Face should fill a reasonable portion of the frame — too small
      // means the person is too far away for a useful skin-detail scan.
      final faceHeightRatio = face.boundingBox.height / image.height;

      if (yaw > 20 || roll > 20 || faceHeightRatio < 0.28) {
        return LiveFaceGuideStatus.tooFarOrTilted;
      }
      return LiveFaceGuideStatus.good;
    } catch (_) {
      return null;
    } finally {
      _busy = false;
    }
  }

  Future<void> dispose() => _faceDetector.close();

  InputImage? _toInputImage(CameraImage image, CameraDescription camera) {
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

    if (image.planes.length < 3) return null;
    final nv21 = _yuv420ToNv21(image);
    return InputImage.fromBytes(
      bytes: nv21,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: InputImageFormat.nv21,
        bytesPerRow: image.width,
      ),
    );
  }

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
        nv21[idUV++] = vPlane.bytes[vIndex];
        nv21[idUV++] = uPlane.bytes[uIndex];
      }
    }

    return nv21;
  }
}