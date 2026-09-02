import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/theme/app_colors.dart';

/// Live barcode/QR scanner with a top-to-bottom animated scan line,
/// matching the look of most retail scanning apps. Pops with the
/// scanned code's raw value once a barcode is detected.
///
/// A single misread frame (motion blur, glare, a partially-covered
/// barcode) can hand back a garbage value, so this doesn't confirm on the
/// first detection — it requires the SAME value to be read
/// [_requiredMatches] times, spaced at least [_sampleInterval] apart, so
/// the user is effectively holding the barcode steady for just over a
/// second before it's accepted.
class BarcodeScanScreen extends StatefulWidget {
  const BarcodeScanScreen({super.key});

  @override
  State<BarcodeScanScreen> createState() => _BarcodeScanScreenState();
}

class _BarcodeScanScreenState extends State<BarcodeScanScreen>
    with SingleTickerProviderStateMixin {
  final MobileScannerController _controller = MobileScannerController(
    formats: const [
      BarcodeFormat.ean13,
      BarcodeFormat.ean8,
      BarcodeFormat.upcA,
      BarcodeFormat.upcE,
      BarcodeFormat.code128,
      BarcodeFormat.qrCode,
    ],
  );

  late final AnimationController _lineController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat(reverse: true);

  /// How many consecutive reads of the same value are required before the
  /// scan is accepted as confirmed.
  static const int _requiredMatches = 4;

  /// Minimum gap between two reads that are allowed to count toward the
  /// match streak — stops a handful of near-identical frames captured in
  /// under 100ms from counting as 4 separate confirmations.
  static const Duration _sampleInterval = Duration(milliseconds: 350);

  bool _handled = false;
  bool _torchOn = false;

  String? _lastValue;
  int _matchCount = 0;
  DateTime? _lastSampleAt;

  @override
  void dispose() {
    _lineController.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    final barcode = capture.barcodes.firstOrNull;
    final value = barcode?.rawValue;
    if (value == null || value.isEmpty) return;

    final now = DateTime.now();
    if (_lastSampleAt != null &&
        now.difference(_lastSampleAt!) < _sampleInterval) {
      // Too soon after the last counted read — throttle so a burst of
      // frames from the same fraction of a second doesn't fast-forward
      // the match streak.
      return;
    }
    _lastSampleAt = now;

    if (value == _lastValue) {
      _matchCount++;
    } else {
      // A different value showed up — the previous streak wasn't a real
      // steady read, so start over on this new value instead.
      _lastValue = value;
      _matchCount = 1;
    }

    if (_matchCount >= _requiredMatches) {
      _handled = true;
      Navigator.of(context).pop(value);
      return;
    }

    // Update the on-screen "confirming" progress dots.
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            MobileScanner(controller: _controller, onDetect: _onDetect),
            IgnorePointer(
              child: CustomPaint(
                painter: _BarcodeFramePainter(),
                child: const SizedBox.expand(),
              ),
            ),
            AnimatedBuilder(
              animation: _lineController,
              builder: (context, _) {
                return IgnorePointer(
                  child: CustomPaint(
                    painter: _ScanLinePainter(progress: _lineController.value),
                    child: const SizedBox.expand(),
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
              top: 8,
              right: 8,
              child: IconButton(
                icon: Icon(
                  _torchOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                  color: Colors.white,
                  size: 26,
                ),
                onPressed: () async {
                  await _controller.toggleTorch();
                  if (!mounted) return;
                  setState(() => _torchOn = !_torchOn);
                },
              ),
            ),
            Positioned(
              top: 28,
              left: 64,
              right: 64,
              child: Text(
                'Align the barcode inside the frame',
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(color: Colors.white),
              ),
            ),
            if (_matchCount > 0)
              Positioned(
                left: 0,
                right: 0,
                bottom: 88,
                child: _ConfirmingIndicator(
                  matched: _matchCount,
                  required: _requiredMatches,
                ),
              ),
            Positioned(
              left: 20,
              right: 20,
              bottom: 34,
              child: Text(
                _matchCount > 0
                    ? 'Hold steady — confirming your barcode…'
                    : 'Scanning happens automatically — hold steady',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: .8),
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

extension<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

/// Small row of dots below the frame showing how many of the required
/// consecutive reads have matched so far — gives the user feedback that
/// something is happening during the brief "hold steady" confirmation
/// window instead of the scan just silently taking a beat longer.
class _ConfirmingIndicator extends StatelessWidget {
  const _ConfirmingIndicator({required this.matched, required this.required});

  final int matched;
  final int required;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(required, (i) {
        final filled = i < matched;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: filled ? 10 : 8,
          height: filled ? 10 : 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: filled
                ? AppColors.primary
                : Colors.white.withValues(alpha: .35),
          ),
        );
      }),
    );
  }
}

/// Rounded frame outlining the scan window, same style as the food
/// camera screen's frame.
class _BarcodeFramePainter extends CustomPainter {
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
    Rect.fromLTWH(32, size.height * .32, size.width - 64, size.height * .24);

/// Draws the teal scan line moving from the top of the frame to the
/// bottom and back, in sync with [_lineController].
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
