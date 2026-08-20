import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/services/rppg_frame_processor.dart';
import '../../core/services/rppg_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/shared_widgets.dart';

/// "Vitals scan" — user holds their face steady in frame for ~20s, the app
/// estimates heart rate on-device from subtle color changes in the skin
/// (CHROM rPPG). No video leaves the phone; nothing is uploaded.
class VitalsScanScreen extends StatefulWidget {
  const VitalsScanScreen({super.key});

  @override
  State<VitalsScanScreen> createState() => _VitalsScanScreenState();
}



enum _ScanState { idle, initializing, scanning, done, error }

class _VitalsScanScreenState extends State<VitalsScanScreen> {
  static const _targetDuration = Duration(seconds: 20);

  CameraController? _controller;
  RppgFrameProcessor? _processor;
  final List<RppgSample> _samples = [];
  DateTime? _startedAt;

  _ScanState _state = _ScanState.idle;
  String? _error;
  double? _resultBpm;
  double? _resultConfidence;
  double? _resultAutocorrBpm;
  double? _resultAutocorrScore;
  String? _debugLog;

  @override
  void dispose() {
    _controller?.dispose();
    _processor?.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _state = _ScanState.initializing;
      _error = null;
      _resultBpm = null;
      _samples.clear();
    });

    try {
      final cameras = await availableCameras();
      final front = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      final controller = CameraController(
        front,
        ResolutionPreset.medium, // enough detail for face ROI, keeps CPU load sane
        enableAudio: false,
      );
      await controller.initialize();
      if (!mounted) return;

      _controller = controller;
      // enableDebug true so processor can log ROI/brightness events to console
      _processor = RppgFrameProcessor(enableDebug: true);
      _startedAt = DateTime.now();

      // Attempt to lock exposure/white-balance/focus for more stable captures.
      try {
        final dyn = controller as dynamic;
        // center the exposure/focus point if supported
        if (dyn.setExposurePoint != null) {
          await dyn.setExposurePoint(Offset(controller.value.previewSize!.width / 2,
              controller.value.previewSize!.height / 2));
        }
        if (dyn.setFocusPoint != null) {
          await dyn.setFocusPoint(Offset(controller.value.previewSize!.width / 2,
              controller.value.previewSize!.height / 2));
        }
        if (dyn.setExposureMode != null) {
          await dyn.setExposureMode(ExposureMode.locked);
        }
        if (dyn.setFocusMode != null) {
          await dyn.setFocusMode(FocusMode.locked);
        }
      } catch (e) {
        // non-fatal: some camera implementations may not support these calls
        debugPrint('[Vitals] exposure/awb lock not available: $e');
      }

      await controller.startImageStream((image) async {
        if (_state != _ScanState.scanning) return;
        final sample = await _processor!.process(image, front);
        if (sample != null && mounted) {
          _samples.add(sample);
          if (DateTime.now().difference(_startedAt!) >= _targetDuration) {
            _finish();
          } else {
            setState(() {}); // repaint progress ring
          }
        }
      });

      setState(() => _state = _ScanState.scanning);
    } catch (e) {
      setState(() {
        _state = _ScanState.error;
        _error = 'Could not access the camera. Check camera permission in '
            'your phone settings and try again.';
      });
    }
  }

  Future<void> _finish() async {
    if (_state != _ScanState.scanning) return;
    setState(() => _state = _ScanState.done);
    await _controller?.stopImageStream();

    final res = RppgService.estimateWithDebug(_samples);
    // Print a short debug summary to console for developers/testers
    try {
      print('[RPPG] bpm=${res.bpm} confidence=${res.confidence.toStringAsFixed(2)} samples=${res.resampled.length} fs=${res.fs}');
      // Print top 5 resampled values and top 5 powers to help tuning
      print('[RPPG] resampled(sample0..4) = ${res.resampled.take(5).map((v) => v.toStringAsFixed(3)).toList()}');
      final topPowers = res.powers.asMap().entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      print('[RPPG] top peaks (bpm,power) = ${topPowers.take(3).map((e) => [(42 + e.key*0.5).toStringAsFixed(1), e.value.toStringAsFixed(2)])}');
    } catch (_) {}

    if (!mounted) return;
    // Build debug log string for UI copy/view
    final sb = StringBuffer();
    sb.writeln('[RPPG] bpm=${res.bpm} confidence=${res.confidence.toStringAsFixed(2)} samples=${res.resampled.length} fs=${res.fs}');
    sb.writeln('[RPPG] resampled(sample0..4) = ${res.resampled.take(10).map((v) => v.toStringAsFixed(3)).toList()}');
    sb.writeln('[RPPG] top powers length=${res.powers.length}');
    if (res.autocorrBpm != null) sb.writeln('[RPPG] autocorr=${res.autocorrBpm!.toStringAsFixed(1)} score=${res.autocorrScore!.toStringAsFixed(2)}');

    if (!mounted) return;
    setState(() {
      if (res.bpm == null) {
        _state = _ScanState.error;
        _error = "Couldn't get a steady enough reading — try again with "
            "better lighting and holding still.";
      } else {
        _resultBpm = res.bpm;
        _resultConfidence = res.confidence;
        _resultAutocorrBpm = res.autocorrBpm;
        _resultAutocorrScore = res.autocorrScore;
        _debugLog = sb.toString();
      }
    });

    await _controller?.dispose();
    _controller = null;
  }

  double get _progress {
    if (_startedAt == null) return 0;
    final elapsed = DateTime.now().difference(_startedAt!).inMilliseconds;
    return (elapsed / _targetDuration.inMilliseconds).clamp(0, 1);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Vitals scan')),
      body: switch (_state) {
        _ScanState.idle => _IntroView(onStart: _start),
        _ScanState.initializing =>
          const Center(child: CircularProgressIndicator()),
        _ScanState.scanning => _ScanningView(
            controller: _controller!,
            progress: _progress,
            sampleCount: _samples.length,
          ),
        _ScanState.done => _ResultView(
            bpm: _resultBpm,
                    confidence: _resultConfidence,
                    autocorrBpm: _resultAutocorrBpm,
                    autocorrScore: _resultAutocorrScore,
                    debugLog: _debugLog,
                    error: null,
                    onRetry: _start,
                    onUseReading: () => Navigator.of(context).pop(_resultBpm),
                  ),
        _ScanState.error => _ResultView(
            bpm: null,
                    confidence: _resultConfidence,
                    error: _error,
                    onRetry: _start,
                    onUseReading: null,
                  ),
      },
    );
  }
}

class _IntroView extends StatelessWidget {
  const _IntroView({required this.onStart});
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.favorite_rounded, size: 64, color: AppColors.danger),
          const SizedBox(height: 20),
          Text('Heart rate scan',
              style:
                  GoogleFonts.sora(fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          const Text(
            'Hold your face steady in frame in good lighting for about 20 '
            'seconds. This estimates your pulse from subtle color changes '
            'in your skin — nothing is recorded or uploaded.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.muted, height: 1.5),
          ),
          const SizedBox(height: 8),
          const Text(
            'This is an estimate, not a medical device — for irregular or '
            'concerning readings, check with a doctor.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.muted, fontSize: 12),
          ),
          const SizedBox(height: 24),
          PrimaryButton(
            label: 'Start scan',
            icon: Icons.videocam_rounded,
            color: AppColors.danger,
            onPressed: onStart,
          ),
        ],
      ),
    );
  }
}

class _ScanningView extends StatelessWidget {
  const _ScanningView(
      {required this.controller,
      required this.progress,
      required this.sampleCount});

  final CameraController controller;
  final double progress;
  final int sampleCount;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Positioned.fill(child: CameraPreview(controller)),
        Positioned(
          bottom: 40,
          child: Column(
            children: [
              SizedBox(
                width: 72,
                height: 72,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: progress,
                      strokeWidth: 5,
                      backgroundColor: Colors.white24,
                      color: AppColors.danger,
                    ),
                    Text('${(progress * 100).toInt()}%',
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                sampleCount < 30 ? 'Finding your face…' : 'Hold still…',
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ResultView extends StatelessWidget {
  const _ResultView({
    this.bpm,
    this.confidence,
    this.autocorrBpm,
    this.autocorrScore,
    this.debugLog,
    this.error,
    required this.onRetry,
    this.onUseReading,
  });
  final double? bpm;
  final double? confidence;
  final double? autocorrBpm;
  final double? autocorrScore;
  final String? debugLog;
  final String? error;
  final VoidCallback onRetry;
  final VoidCallback? onUseReading;

  @override
  Widget build(BuildContext context) {
    if (error != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline_rounded,
                size: 48, color: AppColors.warning),
            const SizedBox(height: 16),
            Text(error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.muted)),
            const SizedBox(height: 20),
            PrimaryButton(
                label: 'Try again',
                icon: Icons.refresh_rounded,
                onPressed: onRetry),
          ],
        ),
      );
    }
    final bool validated = bpm != null && autocorrBpm != null && (bpm! - autocorrBpm!).abs() <= 3.0;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('${bpm?.round() ?? '--'}',
              style:
                  GoogleFonts.sora(fontSize: 56, fontWeight: FontWeight.w800)),
          const Text('BPM',
              style: TextStyle(color: AppColors.muted, letterSpacing: 2)),
          const SizedBox(height: 8),
          if (validated) ...[
            Chip(
              avatar: const Icon(Icons.check_circle, color: Colors.white, size: 16),
              label: const Text('Validated by two methods', style: TextStyle(color: Colors.white)),
              backgroundColor: AppColors.danger,
            ),
            const SizedBox(height: 8),
          ] else if (confidence != null && confidence! >= 6.0) ...[
            Chip(
              avatar: const Icon(Icons.check_circle_outline, color: Colors.white, size: 16),
              label: const Text('High confidence', style: TextStyle(color: Colors.white)),
              backgroundColor: Colors.green,
            ),
            const SizedBox(height: 8),
          ] else if (confidence != null) ...[
            Text('Confidence: ${_fmt(confidence!)}', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
            const SizedBox(height: 8),
          ],

          const Text(
            'Estimate only — not a medical diagnosis. If this feels off or '
            'you have symptoms, check with a doctor.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.muted, fontSize: 12),
          ),
          const SizedBox(height: 16),

          if (onUseReading != null) ...[
            PrimaryButton(
                label: 'Use this reading',
                icon: Icons.check_rounded,
                color: AppColors.danger,
                onPressed: onUseReading),
            const SizedBox(height: 10),
          ],

          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Scan again'),
              ),
              const SizedBox(width: 8),
              if (debugLog != null) ...[
                OutlinedButton.icon(
                  onPressed: () async {
                    await showDialog<void>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Debug details'),
                        content: SingleChildScrollView(child: Text(debugLog!)),
                        actions: [
                          TextButton(
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: debugLog!));
                                Navigator.of(ctx).pop();
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Debug copied')));
                              },
                              child: const Text('Copy')),
                          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Close')),
                        ],
                      ),
                    );
                  },
                  icon: const Icon(Icons.bug_report, size: 18),
                  label: const Text('Details'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  static String _fmt(double v) => v.isFinite ? v.toStringAsFixed(2) : 'N/A';
}
