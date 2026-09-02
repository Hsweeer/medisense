import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/services/rppg_frame_processor.dart';
import '../../core/services/rppg_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/shared_widgets.dart';
import 'vitals_history_screen.dart';

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
  // 18s — short enough that the scan doesn't feel like a long wait, while
  // still giving the estimator (see rppg_service.dart) enough samples and
  // a couple of independent windows to work with. Paired with the
  // low-confidence fallback in RppgService, the scan now always ends with
  // a BPM result instead of a hard "try again" failure.
  static const _targetDuration = Duration(seconds: 18);

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

  // Debug overlay values
  final int _acceptedFrames = 0;
  final int _rejectedFrames = 0;
  final String _lastRejection = '';
  final String _lastFrameDebug = '';
  Rect? _lastFaceBox;
  Rect? _lastTransformedFace;
  Rect? _lastRoi;
  double? _lastBrightness;
  double? _lastDarkPct;
  double? _lastSatPct;

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
        ResolutionPreset
            .medium, // enough detail for face ROI, keeps CPU load sane
        enableAudio: false,
      );
      await controller.initialize();
      if (!mounted) return;

      _controller = controller;
      // Debug disabled in production path
      _processor = RppgFrameProcessor();
      _startedAt = DateTime.now();

      // Attempt to lock exposure/white-balance/focus for more stable captures.
      try {
        final dyn = controller as dynamic;
        // center the exposure/focus point if supported — use normalized
        // coordinates (0..1) instead of raw pixel values. Some camera
        // implementations expect normalized coordinates; passing pixel
        // coordinates caused incorrect focus/exposure placement.
        final centerPoint = const Offset(0.5, 0.5);
        if (dyn.setExposurePoint != null) {
          await dyn.setExposurePoint(centerPoint);
        }
        if (dyn.setFocusPoint != null) {
          await dyn.setFocusPoint(centerPoint);
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

      DateTime lastUiUpdate = DateTime.now();
      await controller.startImageStream((image) async {
        if (_state != _ScanState.scanning) return;
        final sample = await _processor!.process(image, front);
        if (sample != null && mounted) {
          _samples.add(sample);
        }
        // Check elapsed time regardless of whether this particular frame
        // was accepted — otherwise a run of rejected frames (bad lighting,
        // too much motion, face detector still warming up) could leave the
        // scan hanging past its target duration with no feedback at all,
        // rather than ending on time and showing a clear result or error.
        if (!mounted || _state != _ScanState.scanning) return;
        if (DateTime.now().difference(_startedAt!) >= _targetDuration) {
          _finish();
          return;
        }
        // Throttle rebuilds to a few times a second — calling setState on
        // every single camera frame (15-30/sec) is unnecessary UI churn.
        if (DateTime.now().difference(lastUiUpdate).inMilliseconds >= 250) {
          lastUiUpdate = DateTime.now();
          setState(() {});
        }
      });

      setState(() => _state = _ScanState.scanning);
    } catch (e) {
      setState(() {
        _state = _ScanState.error;
        _error =
            'Could not access the camera. Check camera permission in '
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
      print(
        '[RPPG] bpm=${res.bpm} confidence=${res.confidence.toStringAsFixed(2)} samples=${res.resampled.length} fs=${res.fs}',
      );
      // Print top 5 resampled values and top 5 powers to help tuning
      print(
        '[RPPG] resampled(sample0..4) = ${res.resampled.take(5).map((v) => v.toStringAsFixed(3)).toList()}',
      );
      final topPowers = res.powers.asMap().entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      print(
        '[RPPG] top peaks (bpm,power) = ${topPowers.take(3).map((e) => [(42 + e.key * 0.5).toStringAsFixed(1), e.value.toStringAsFixed(4)])}',
      );

      // Additional diagnostics
      print(
        '[RPPG] diagnosticReason=${res.diagnosticReason} fullPeak=${res.fullWindowPeak} fullMedian=${res.fullWindowMedian} windowsStdDev=${res.windowsStdDev} acceptedWindows=${res.acceptedWindowCount}',
      );
      print(
        '[RPPG] windowCandidates=${res.windowCandidates} windowRatios=${res.windowRatios} windowAutocorrs=${res.windowAutocorrs}',
      );
      if (_processor != null) {
        print(
          '[RPPG] processor accepted=${_processor!.acceptedFrames} rejected=${_processor!.rejectedFrames} rejectionCounts=${_processor!.rejectionCounts} lastFrame=${_processor!.lastFrameDebug} lastReject=${_processor!.lastRejectionReason}',
        );
      }
    } catch (_) {}

    if (!mounted) return;
    // Build debug log string for UI copy/view
    final sb = StringBuffer();
    sb.writeln(
      '[RPPG] bpm=${res.bpm} confidence=${res.confidence.toStringAsFixed(2)} samples=${res.resampled.length} fs=${res.fs}',
    );
    sb.writeln(
      '[RPPG] resampled(sample0..4) = ${res.resampled.take(10).map((v) => v.toStringAsFixed(3)).toList()}',
    );
    sb.writeln('[RPPG] top powers length=${res.powers.length}');
    if (res.autocorrBpm != null) {
      sb.writeln(
        '[RPPG] autocorr=${res.autocorrBpm!.toStringAsFixed(1)} score=${res.autocorrScore!.toStringAsFixed(2)}',
      );
    }

    if (!mounted) return;
    setState(() {
      if (res.bpm == null) {
        _state = _ScanState.error;
        _error =
            "Couldn't get a steady enough reading — try again with "
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
      appBar: AppBar(
        title: const Text('Vitals scan'),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.success,
              elevation: 0,
            ),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const VitalsHistoryScreen()),
            ),
            child: Text(
              'History',
              style: GoogleFonts.manrope(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      body: switch (_state) {
        _ScanState.idle => _IntroView(onStart: _start),
        _ScanState.initializing => const Center(
          child: CircularProgressIndicator(),
        ),
        _ScanState.scanning => _ScanningView(
          controller: _controller!,
          progress: _progress,
          sampleCount: _samples.length,
          processor: _processor,
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
          Text(
            'Heart rate scan',
            style: GoogleFonts.sora(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          const Text(
            'Hold your face steady in frame in good lighting for about 18 '
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
  const _ScanningView({
    required this.controller,
    required this.progress,
    required this.sampleCount,
    this.processor,
  });

  final CameraController controller;
  final double progress;
  final int sampleCount;
  final RppgFrameProcessor? processor;

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
                    Text(
                      '${(progress * 100).toInt()}%',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                _liveStatusText(),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Translates the frame processor's last rejection reason into a short,
  /// actionable message — so the person finds out *during* the scan that
  /// they should hold steadier or find better light, instead of only
  /// learning the scan failed after waiting the full duration.
  String _liveStatusText() {
    if (sampleCount < 15) {
      final reason = processor?.lastRejectionReason ?? '';
      switch (reason) {
        case 'FACE_TOO_SMALL':
          return 'Move a little closer';
        case 'EXCESSIVE_MOTION':
        case 'ROI_NOT_STABLE':
          return 'Hold your phone a bit steadier';
        case 'BRIGHTNESS_JUMP':
          return 'Try to keep the lighting steady';
        case 'FACE_NOT_DETECTED':
        default:
          return 'Finding your face…';
      }
    }
    return 'Hold still — reading your pulse…';
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
            const Icon(
              Icons.error_outline_rounded,
              size: 48,
              color: AppColors.warning,
            ),
            const SizedBox(height: 16),
            Text(
              error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.muted),
            ),
            const SizedBox(height: 20),
            PrimaryButton(
              label: 'Try again',
              icon: Icons.refresh_rounded,
              onPressed: onRetry,
            ),
          ],
        ),
      );
    }
    final bool validated =
        bpm != null &&
        autocorrBpm != null &&
        (bpm! - autocorrBpm!).abs() <= 3.0;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '${bpm?.round() ?? '--'}',
            style: GoogleFonts.sora(fontSize: 56, fontWeight: FontWeight.w800),
          ),
          const Text(
            'BPM',
            style: TextStyle(color: AppColors.muted, letterSpacing: 2),
          ),
          const SizedBox(height: 8),
          if (validated) ...[
            Chip(
              avatar: const Icon(
                Icons.check_circle,
                color: Colors.white,
                size: 16,
              ),
              label: const Text(
                'Signal checks agree',
                style: TextStyle(color: Colors.white),
              ),
              backgroundColor: AppColors.danger,
            ),
            const SizedBox(height: 8),
          ] else if (confidence != null && confidence! >= 6.0) ...[
            Chip(
              avatar: const Icon(
                Icons.check_circle_outline,
                color: Colors.white,
                size: 16,
              ),
              label: const Text(
                'High confidence',
                style: TextStyle(color: Colors.white),
              ),
              backgroundColor: Colors.green,
            ),
            const SizedBox(height: 8),
          ] else if (confidence != null) ...[
            const Chip(
              avatar: Icon(Icons.info_outline, color: Colors.white, size: 16),
              label: Text(
                'Low confidence — hold still & try again for accuracy',
                style: TextStyle(color: Colors.white, fontSize: 12),
              ),
              backgroundColor: Colors.orange,
            ),
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
              onPressed: onUseReading,
            ),
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
                    final shouldCopy = await AppDialog.confirm(
                      context: context,
                      title: 'Debug details',
                      message: debugLog!,
                      confirmText: 'Copy',
                      cancelText: 'Close',
                      accentColor: AppColors.ai,
                      icon: Icons.bug_report_rounded,
                    );
                    if (!shouldCopy || !context.mounted) return;
                    await Clipboard.setData(ClipboardData(text: debugLog!));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Debug copied')),
                      );
                    }
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
