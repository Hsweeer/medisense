import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';
import 'dart:math';

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
  RppgFrameProcessor({this.enableDebug = false})
      : _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      performanceMode: FaceDetectorMode.fast,
      enableTracking: false,
    ),
  );

  final FaceDetector _faceDetector;
  final bool enableDebug;
  bool _busy = false;

  Rect? _smoothedRoi;
  int _stableFrames = 0; // consecutive stable frames
  double? _lastBrightness;

  // Debug counters and diagnostics exposed for temporary QA overlay
  int acceptedFrames = 0;
  int rejectedFrames = 0;
  Map<String, int> rejectionCounts = {};
  String lastRejectionReason = '';
  String lastFrameDebug = ''; // JSON-like summary for last processed frame

  void _countRejection(String reason) {
    rejectedFrames++;
    lastRejectionReason = reason;
    rejectionCounts[reason] = (rejectionCounts[reason] ?? 0) + 1;
  }

  void _countAcceptance(String debug) {
    acceptedFrames++;
    lastFrameDebug = debug;
  }

  /// Call for every frame from `CameraController.startImageStream`.
  /// Returns null while no face is found, a frame is skipped (already busy
  /// processing a previous one), or the frame is otherwise unusable.
  Future<RppgSample?> process(CameraImage image, CameraDescription camera) async {
    if (_busy) return null; // drop frames instead of queueing — keeps up with live video
    _busy = true;
    try {
      if (enableDebug) print('[RPPG] Frame received: ${DateTime.now().toIso8601String()} size=${image.width}x${image.height} format=${image.format.group}');

      // Convert camera frame into an ML Kit InputImage (with rotation metadata)
      final inputImage = _toInputImage(image, camera);
      if (inputImage == null) {
        _countRejection('INPUTIMAGE_CREATION_FAILED');
        if (enableDebug) print('[RPPG] Could not create InputImage');
        return null;
      }
      if (enableDebug) print('[RPPG] InputImage created (rotation=${camera.sensorOrientation})');

      // Run face detection on the rotated/normalized input image that ML Kit
      // expects. The detected boundingBox is returned in the coordinate
      // system of the InputImage (respecting the rotation we provided).
      final faces = await _faceDetector.processImage(inputImage);
      if (faces.isEmpty) {
        _countRejection('FACE_NOT_DETECTED');
        if (enableDebug) print('[RPPG] No face detected');
        return null;
      }
      if (enableDebug) print('[RPPG] Faces detected: ${faces.length}');

      // Pick the largest face
      final face = faces.reduce(
              (a, b) => a.boundingBox.width * a.boundingBox.height >
              b.boundingBox.width * b.boundingBox.height
              ? a
              : b);
      if (enableDebug) print('[RPPG] MLKit face bbox (InputImage coords): ${face.boundingBox}');

      // Transform the ML Kit bounding box (InputImage coordinates) into the
      // raw CameraImage pixel coordinates where our RGB extractor reads
      // bytes. This accounts for the rotation metadata ML Kit used and
      // mirrors the box for front-facing cameras so the ROI maps to the
      // physical location on the sensor buffer.
      final transformedFace = _mapBoundingBoxToCameraImage(
          face.boundingBox, image, camera);
      if (transformedFace == null) {
        _countRejection('FACE_TRANSFORM_FAILED');
        if (enableDebug) print('[RPPG] Face transform failed');
        return null;
      }
      if (enableDebug) print('[RPPG] Transformed face bbox (camera coords): $transformedFace');

      // Validate face size: require a minimum face size relative to frame
      // to avoid tiny noisy detections.
      if (transformedFace.width < image.width * 0.12 || transformedFace.height < image.height * 0.12) {
        _countRejection('FACE_TOO_SMALL');
        if (enableDebug) print('[RPPG] Face too small: ${transformedFace.width}x${transformedFace.height} (frame ${image.width}x${image.height})');
        return null;
      }

      // Build a stable forehead ROI inside the transformed face rectangle.
      // We choose a small, centered upper region to avoid eyes, eyebrows,
      // hairline, nose and mouth. The ROI is intentionally conservative.
      final roi = _foreheadRoi(transformedFace, image);
      if (roi == null) {
        _countRejection('ROI_INVALID');
        if (enableDebug) print('[RPPG] ROI invalid or out of bounds');
        return null;
      }
      if (enableDebug) print('[RPPG] Forehead ROI (camera coords): $roi');

      // Movement check: compare candidate ROI center to smoothed ROI and
      // drop frames during rapid motion (helps reject motion-contaminated
      // pixels). This uses a normalized movement threshold relative to face
      // width so it scales across phones.
      if (_smoothedRoi == null) {
        _smoothedRoi = roi;
        _stableFrames = 1;
      } else {
        final dx = (roi.center.dx - _smoothedRoi!.center.dx) / (roi.width);
        final dy = (roi.center.dy - _smoothedRoi!.center.dy) / (roi.width);
        final move = sqrt(dx * dx + dy * dy);
        if (enableDebug) print('[RPPG] Movement test: move=${move.toStringAsFixed(4)}');
        const movementThreshold = 0.18; // was 0.12 — natural hand-holding
        // movement was rejecting too many otherwise-good frames; a phone
        // held in-hand (not on a stand) always has some micro-motion.
        if (move > movementThreshold) {
          _stableFrames = 0;
          _countRejection('EXCESSIVE_MOTION');
          if (enableDebug) print('[RPPG] ROI moved too fast (move=${move.toStringAsFixed(3)}) — dropping frame');
        } else {
          _stableFrames = (_stableFrames + 1).clamp(0, 10);
        }
        _smoothedRoi = Rect.lerp(_smoothedRoi, roi, 0.3) ?? roi;
      }

      // Require a few stable frames before accepting samples
      if (_stableFrames < 3) {
        _countRejection('ROI_NOT_STABLE');
        return null;
      }

      // Ensure ROI is still fully inside the image before sampling
      final clipped = Rect.fromLTWH(
        _smoothedRoi!.left.clamp(0, image.width - 1),
        _smoothedRoi!.top.clamp(0, image.height - 1),
        _smoothedRoi!.width.clamp(1, image.width.toDouble()),
        _smoothedRoi!.height.clamp(1, image.height.toDouble()),
      );

      // Basic area check
      if (clipped.width * clipped.height < 36) {
        _countRejection('ROI_TOO_SMALL');
        if (enableDebug) print('[RPPG] ROI too small after clip');
        return null;
      }

      // Finally extract mean RGB from the (validated) smoothed ROI. The
      // _meanRgbInBox contains additional brightness jump checks and will
      // return null if the exposure jumped.
      final sample = _meanRgbInBox(image, clipped);
      if (sample == null) {
        // _meanRgbInBox already counts rejection with reasons like BRIGHTNESS_JUMP
        return null;
      }

      // Accepted
      final debug = '{"roi": ${clipped.toString()}, "r": ${sample.r.toStringAsFixed(2)}, "g": ${sample.g.toStringAsFixed(2)}, "b": ${sample.b.toStringAsFixed(2)}}';
      _countAcceptance(debug);
      if (enableDebug) print('[RPPG] Accepted frame: $debug');
      return sample;
    } catch (e) {
      if (enableDebug) print('[RPPG] process error: $e');
      _countRejection('PROCESS_EXCEPTION');
      return null; // a single bad frame shouldn't crash the scan
    } finally {
      _busy = false;
    }
  }

  /// Map an ML Kit [boundingBox] (which is in InputImage coordinates — i.e.
  /// the image after ML Kit rotation was applied) into the raw CameraImage
  /// pixel coordinates used by our RGB extractor. This does two things:
  /// 1) Rotates the rectangle by -rotationDegrees around the image center to
  ///    undo the rotation ML Kit applied when creating the InputImage, and
  /// 2) If the camera is front-facing, mirror horizontally because many
  ///    front previews are mirrored and ML Kit may have processed a mirrored
  ///    coordinate system. The exact mapping depends on the rotation value
  ///    passed to ML Kit when creating InputImage; we stored that as
  ///    `rotationCompensation` in _toInputImage. Rotating points around the
  ///    image center and optionally flipping keeps this code resilient to
  ///    different sensor orientations.
  Rect? _mapBoundingBoxToCameraImage(Rect boundingBox, CameraImage image, CameraDescription camera) {
    // InputImage was created with metadata size = (image.width, image.height)
    final width = image.width.toDouble();
    final height = image.height.toDouble();

    // Raw camera buffer uses the same width/height values; ML Kit's
    // boundingBox coordinates are relative to the rotated InputImage we
    // provided. To map back, rotate coordinates around center by -rotation.
    final rotationCompensation =
    camera.lensDirection == CameraLensDirection.front
        ? camera.sensorOrientation % 360
        : (camera.sensorOrientation + 360) % 360;
    final angleRad = -rotationCompensation * pi / 180.0;

    // helper to rotate a point about image center
    Offset rotate(Offset p) {
      final cx = width / 2.0;
      final cy = height / 2.0;
      final tx = p.dx - cx;
      final ty = p.dy - cy;
      final rx = tx * cos(angleRad) - ty * sin(angleRad);
      final ry = tx * sin(angleRad) + ty * cos(angleRad);
      return Offset(rx + cx, ry + cy);
    }

    // Get the four corners of the ML Kit box, rotate them back to raw coords
    final tl = rotate(Offset(boundingBox.left, boundingBox.top));
    final tr = rotate(Offset(boundingBox.right, boundingBox.top));
    final bl = rotate(Offset(boundingBox.left, boundingBox.bottom));
    final br = rotate(Offset(boundingBox.right, boundingBox.bottom));

    // Optionally mirror horizontally for front camera so that the ROI ends
    // up on the same side of the face in the raw buffer as it appears to
    // the user. This mirrors around the vertical center line.
    double flipX(double x) => width - x;
    if (camera.lensDirection == CameraLensDirection.front) {
      final rTl = Offset(flipX(tl.dx), tl.dy);
      final rTr = Offset(flipX(tr.dx), tr.dy);
      final rBl = Offset(flipX(bl.dx), bl.dy);
      final rBr = Offset(flipX(br.dx), br.dy);
      // reassign
      // compute axis-aligned bounding box containing the transformed corners
      final left = [rTl.dx, rTr.dx, rBl.dx, rBr.dx].reduce(min);
      final right = [rTl.dx, rTr.dx, rBl.dx, rBr.dx].reduce(max);
      final top = [rTl.dy, rTr.dy, rBl.dy, rBr.dy].reduce(min);
      final bottom = [rTl.dy, rTr.dy, rBl.dy, rBr.dy].reduce(max);
      return Rect.fromLTWH(left, top, right - left, bottom - top);
    } else {
      final left = [tl.dx, tr.dx, bl.dx, br.dx].reduce(min);
      final right = [tl.dx, tr.dx, bl.dx, br.dx].reduce(max);
      final top = [tl.dy, tr.dy, bl.dy, br.dy].reduce(min);
      final bottom = [tl.dy, tr.dy, bl.dy, br.dy].reduce(max);
      return Rect.fromLTWH(left, top, right - left, bottom - top);
    }
  }

  /// Return a conservative forehead ROI inside [faceRect] clamped to [image].
  /// This region is intentionally small and placed in the upper center of
  /// the face to avoid eyes, eyebrows, hairline and other motion sources.
  Rect? _foreheadRoi(Rect faceRect, CameraImage image) {
    // Start a bit below the top edge of the face to avoid hairline
    final x = faceRect.left + faceRect.width * 0.22;
    final w = faceRect.width * 0.56;
    final y = faceRect.top + faceRect.height * 0.06; // slightly below top
    final h = faceRect.height * 0.16; // narrow strip across upper forehead

    final roi = Rect.fromLTWH(x, y, w, h);

    // Clamp to image bounds
    final left = roi.left.clamp(0.0, image.width - 1.0);
    final top = roi.top.clamp(0.0, image.height - 1.0);
    final right = roi.right.clamp(1.0, image.width.toDouble());
    final bottom = roi.bottom.clamp(1.0, image.height.toDouble());

    if (right <= left || bottom <= top) return null;
    final clipped = Rect.fromLTWH(left, top, right - left, bottom - top);

    // Ensure ROI occupies a reasonable number of pixels
    if (clipped.width * clipped.height < 100) return null;

    return clipped;
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

    int darkCount = 0;
    int satCount = 0;

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
          final lum = (0.2126 * r + 0.7152 * g + 0.0722 * b);
          if (lum < 30) darkCount++;
          if (r > 250 || g > 250 || b > 250) satCount++;
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
          final lum = (0.2126 * r + 0.7152 * g + 0.0722 * b);
          if (lum < 30) darkCount++;
          if (r > 250 || g > 250 || b > 250) satCount++;
          count++;
        }
      }
    } else {
      _countRejection('UNSUPPORTED_FORMAT');
      return null; // unsupported format on this device
    }

    if (count == 0) {
      _countRejection('NO_PIXELS');
      return null;
    }
    final sample = RppgSample(
      timestampMs: DateTime.now().millisecondsSinceEpoch,
      r: sumR / count,
      g: sumG / count,
      b: sumB / count,
    );

    // Brightness stability check: drop frames where exposure changed
    final brightness = (sample.r + sample.g + sample.b) / 3.0;
    final darkPct = (darkCount / count) * 100.0;
    final satPct = (satCount / count) * 100.0;

    if (enableDebug) print('[RPPG] ROI pixels=$count brightness=${brightness.toStringAsFixed(1)} dark%=${darkPct.toStringAsFixed(1)} sat%=${satPct.toStringAsFixed(1)}');

    if (_lastBrightness != null) {
      final rel = (brightness - _lastBrightness!).abs() / (_lastBrightness! + 1e-6);
      if (rel > 0.35) {
        // was 0.28 — exposure lock (attempted in VitalsScanScreen) silently
        // fails on some devices, so normal auto-exposure micro-adjustments
        // shouldn't be treated as harshly as a real lighting change.
        if (enableDebug) print('[RPPG] brightness jump (rel=${rel.toStringAsFixed(2)}) — dropping frame');
        _lastBrightness = brightness;
        _countRejection('BRIGHTNESS_JUMP');
        return null;
      }
    }
    _lastBrightness = brightness;

    // Keep logging stats in lastFrameDebug even for accepted frames
    lastFrameDebug = '{"pixels": $count, "brightness": ${brightness.toStringAsFixed(2)}, "dark_pct": ${darkPct.toStringAsFixed(2)}, "sat_pct": ${satPct.toStringAsFixed(2)}}';

    return sample;
  }
}