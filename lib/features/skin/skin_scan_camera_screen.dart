import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/services/live_face_guide_processor.dart';
import '../../core/theme/app_colors.dart';

/// Live camera screen for skin scans — shows a real-time face-positioning
/// guide (like the document-edge feedback during a prescription scan) so
/// the person can tell the app is actively reading their face before they
/// capture, rather than just tapping a plain camera shutter blind.
class SkinScanCameraScreen extends StatefulWidget {
  const SkinScanCameraScreen({super.key});

  @override
  State<SkinScanCameraScreen> createState() => _SkinScanCameraScreenState();
}

class _SkinScanCameraScreenState extends State<SkinScanCameraScreen> {
  CameraController? _controller;
  LiveFaceGuideProcessor? _processor;

  LiveFaceGuideStatus _status = LiveFaceGuideStatus.noFace;
  bool _capturing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _controller?.dispose();
    _processor?.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    try {
      final cameras = await availableCameras();
      final front = cameras.firstWhere(
            (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      final controller = CameraController(
        front,
        ResolutionPreset.high, // skin detail benefits from more resolution
        enableAudio: false,
      );
      await controller.initialize();
      if (!mounted) return;

      _controller = controller;
      _processor = LiveFaceGuideProcessor();

      await controller.startImageStream((image) async {
        if (_capturing) return;
        final result = await _processor!.process(image, front);
        if (result != null && mounted) {
          setState(() => _status = result);
        }
      });

      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        setState(() => _error =
        'Could not access the camera. Check camera permission in your phone settings and try again.');
      }
    }
  }

  Future<void> _capture() async {
    if (_capturing || _controller == null || !_controller!.value.isInitialized) return;
    setState(() => _capturing = true);
    try {
      await _controller!.stopImageStream();
      final file = await _controller!.takePicture();
      if (!mounted) return;
      Navigator.of(context).pop(file.path);
    } catch (e) {
      if (mounted) {
        setState(() {
          _capturing = false;
          _error = 'Could not capture the photo. Please try again.';
        });
      }
    }
  }

  String get _statusText {
    switch (_status) {
      case LiveFaceGuideStatus.noFace:
        return 'Position your face in the oval';
      case LiveFaceGuideStatus.tooFarOrTilted:
        return 'Move closer and face the camera directly';
      case LiveFaceGuideStatus.good:
        return _capturing ? 'Capturing…' : 'Good — hold still and tap to scan';
    }
  }

  Color get _guideColor {
    if (_capturing) return AppColors.ai;
    switch (_status) {
      case LiveFaceGuideStatus.noFace:
        return Colors.white.withValues(alpha: .55);
      case LiveFaceGuideStatus.tooFarOrTilted:
        return AppColors.warning;
      case LiveFaceGuideStatus.good:
        return AppColors.success;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_controller != null && _controller!.value.isInitialized)
              Positioned.fill(child: CameraPreview(_controller!))
            else
              const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),

            // Dimmed background outside the oval guide.
            if (_controller != null && _controller!.value.isInitialized)
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _OvalMaskPainter(color: Colors.black.withValues(alpha: .45)),
                  ),
                ),
              ),

            // The oval face guide itself, colored by live status.
            if (_controller != null && _controller!.value.isInitialized)
              Center(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 260,
                  height: 340,
                  decoration: BoxDecoration(
                    shape: BoxShape.rectangle,
                    borderRadius: BorderRadius.circular(140),
                    border: Border.all(color: _guideColor, width: 3),
                  ),
                ),
              ),

            // Top bar.
            Positioned(
              top: 8,
              left: 8,
              child: IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),

            // Live status + capture button.
            Positioned(
              left: 0,
              right: 0,
              bottom: 30,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                      child: Text(_error!,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.sora(color: Colors.white, fontSize: 13)),
                    )
                  else
                    Text(_statusText,
                        style: GoogleFonts.sora(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700)),
                  const SizedBox(height: 20),
                  GestureDetector(
                    onTap: _status == LiveFaceGuideStatus.good ? _capture : null,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 70,
                      height: 70,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _status == LiveFaceGuideStatus.good
                            ? AppColors.ai
                            : Colors.white.withValues(alpha: .25),
                        border: Border.all(color: Colors.white, width: 3),
                      ),
                      child: _capturing
                          ? const Padding(
                        padding: EdgeInsets.all(18),
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2.5),
                      )
                          : const Icon(Icons.face_retouching_natural_rounded,
                          color: Colors.white, size: 30),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Darkens everything outside the oval guide so attention is drawn to
/// where the face should go — purely cosmetic, doesn't affect the actual
/// captured photo (which is the full, unmasked camera frame).
class _OvalMaskPainter extends CustomPainter {
  _OvalMaskPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final ovalRect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: 260,
      height: 340,
    );
    final ovalPath = Path()
      ..addRRect(RRect.fromRectAndRadius(ovalRect, const Radius.circular(140)));
    final fullPath = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final maskPath = Path.combine(PathOperation.difference, fullPath, ovalPath);
    canvas.drawPath(maskPath, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _OvalMaskPainter oldDelegate) => false;
}