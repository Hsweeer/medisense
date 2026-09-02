import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

class FoodScanCameraScreen extends StatefulWidget {
  const FoodScanCameraScreen({super.key});

  @override
  State<FoodScanCameraScreen> createState() => _FoodScanCameraScreenState();
}

class _FoodScanCameraScreenState extends State<FoodScanCameraScreen>
    with SingleTickerProviderStateMixin {
  CameraController? _controller;
  String? _error;
  bool _capturing = false;

  late final AnimationController _lineController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat(reverse: true);

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  @override
  void dispose() {
    _lineController.dispose();
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) throw StateError('No camera available');
      final camera = cameras.firstWhere(
        (item) => item.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        camera,
        ResolutionPreset.high,
        enableAudio: false,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
    } catch (_) {
      if (mounted) {
        setState(() {
          _error =
              'Could not open the camera. Check camera permission and try again.';
        });
      }
    }
  }

  Future<void> _takePhoto() async {
    final controller = _controller;
    if (_capturing || controller == null || !controller.value.isInitialized) {
      return;
    }
    setState(() => _capturing = true);
    try {
      final photo = await controller.takePicture();
      if (mounted) Navigator.of(context).pop(photo);
    } catch (_) {
      if (mounted) {
        setState(() {
          _capturing = false;
          _error = 'Could not capture the photo. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ready = _controller?.value.isInitialized == true;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (ready)
              CameraPreview(_controller!)
            else
              const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            if (ready)
              IgnorePointer(child: CustomPaint(painter: _FoodFramePainter())),
            if (ready)
              AnimatedBuilder(
                animation: _lineController,
                builder: (context, _) {
                  return IgnorePointer(
                    child: CustomPaint(
                      painter: _ScanLinePainter(
                        progress: _lineController.value,
                      ),
                    ),
                  );
                },
              ),
            Positioned(
              top: 8,
              left: 8,
              child: IconButton(
                icon: const Icon(
                  Icons.close_rounded,
                  color: Colors.white,
                  size: 28,
                ),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            Positioned(
              top: 28,
              left: 64,
              right: 24,
              child: Text(
                'Place your food inside the frame',
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(color: Colors.white),
              ),
            ),
            Positioned(
              left: 20,
              right: 20,
              bottom: 28,
              child: Column(
                children: [
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  GestureDetector(
                    onTap: ready ? _takePhoto : null,
                    child: Container(
                      width: 76,
                      height: 76,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: ready ? AppColors.primary : Colors.grey,
                        border: Border.all(color: Colors.white, width: 4),
                      ),
                      child: _capturing
                          ? const Padding(
                              padding: EdgeInsets.all(22),
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(
                              Icons.camera_alt_rounded,
                              color: Colors.white,
                              size: 30,
                            ),
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

class _FoodFramePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: .9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawRRect(
      RRect.fromRectAndRadius(_frameRect(size), const Radius.circular(20)),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

Rect _frameRect(Size size) =>
    Rect.fromLTWH(24, size.height * .23, size.width - 48, size.height * .42);

/// Draws the teal scan line moving from the top of the food frame to the
/// bottom and back, giving the same live-scanning feel as the barcode
/// scanner.
class _ScanLinePainter extends CustomPainter {
  _ScanLinePainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final frame = _frameRect(size);
    final y = frame.top + frame.height * progress;

    final linePaint = Paint()
      ..shader = LinearGradient(
        colors: [
          AppColors.primary.withValues(alpha: 0),
          AppColors.primary,
          AppColors.primary.withValues(alpha: 0),
        ],
      ).createShader(Rect.fromLTWH(frame.left, y - 1, frame.width, 2))
      ..strokeWidth = 2.5;

    canvas.drawLine(
      Offset(frame.left + 6, y),
      Offset(frame.right - 6, y),
      linePaint,
    );

    final glowPaint = Paint()
      ..color = AppColors.primary.withValues(alpha: .25)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawLine(
      Offset(frame.left + 6, y),
      Offset(frame.right - 6, y),
      glowPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _ScanLinePainter oldDelegate) =>
      oldDelegate.progress != progress;
}
