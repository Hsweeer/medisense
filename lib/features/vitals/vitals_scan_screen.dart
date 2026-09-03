import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
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

/// Broad, well-known resting-heart-rate bands. Purely informational —
/// never a diagnosis — and shown alongside the same "see a doctor" note
/// that already exists on the result screen.
enum _BpmZone { low, resting, elevated }

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
        if (kDebugMode) {
          debugPrint('[Vitals] exposure/awb lock not available: $e');
        }
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

    // Developer-only diagnostics — never shown or logged in release builds.
    String? debugLog;
    if (kDebugMode) {
      debugPrint(
        '[RPPG] bpm=${res.bpm} confidence=${res.confidence.toStringAsFixed(2)} samples=${res.resampled.length} fs=${res.fs}',
      );
      final topPowers = res.powers.asMap().entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      debugPrint(
        '[RPPG] top peaks (bpm,power) = ${topPowers.take(3).map((e) => [(42 + e.key * 0.5).toStringAsFixed(1), e.value.toStringAsFixed(4)])}',
      );
      debugPrint(
        '[RPPG] diagnosticReason=${res.diagnosticReason} fullPeak=${res.fullWindowPeak} fullMedian=${res.fullWindowMedian} windowsStdDev=${res.windowsStdDev} acceptedWindows=${res.acceptedWindowCount}',
      );
      if (_processor != null) {
        debugPrint(
          '[RPPG] processor accepted=${_processor!.acceptedFrames} rejected=${_processor!.rejectedFrames} rejectionCounts=${_processor!.rejectionCounts}',
        );
      }

      final sb = StringBuffer();
      sb.writeln(
        '[RPPG] bpm=${res.bpm} confidence=${res.confidence.toStringAsFixed(2)} samples=${res.resampled.length} fs=${res.fs}',
      );
      if (res.autocorrBpm != null) {
        sb.writeln(
          '[RPPG] autocorr=${res.autocorrBpm!.toStringAsFixed(1)} score=${res.autocorrScore!.toStringAsFixed(2)}',
        );
      }
      debugLog = sb.toString();
    }

    if (!mounted) return;

    if (res.bpm == null) {
      HapticFeedback.mediumImpact();
      setState(() {
        _state = _ScanState.error;
        _error =
            "Couldn't get a steady enough reading — try again with "
            "better lighting and holding still.";
      });
    } else {
      HapticFeedback.lightImpact();
      setState(() {
        _resultBpm = res.bpm;
        _resultConfidence = res.confidence;
        _resultAutocorrBpm = res.autocorrBpm;
        _resultAutocorrScore = res.autocorrScore;
        _debugLog = debugLog;
      });
    }

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
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        backgroundColor: _state == _ScanState.scanning
            ? Colors.transparent
            : AppColors.paper,
        surfaceTintColor: AppColors.paper,
        elevation: 0,
        foregroundColor: _state == _ScanState.scanning
            ? Colors.white
            : AppColors.ink,
        title: const Text('Heart rate scan'),
      ),
      extendBodyBehindAppBar: _state == _ScanState.scanning,
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: switch (_state) {
          _ScanState.idle => _IntroView(
            key: const ValueKey('idle'),
            onStart: _start,
          ),
          _ScanState.initializing => const Center(
            key: ValueKey('init'),
            child: CircularProgressIndicator(color: AppColors.danger),
          ),
          _ScanState.scanning => _ScanningView(
            key: const ValueKey('scanning'),
            controller: _controller!,
            progress: _progress,
            sampleCount: _samples.length,
            processor: _processor,
          ),
          _ScanState.done => _ResultView(
            key: const ValueKey('done'),
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
            key: const ValueKey('error'),
            bpm: null,
            confidence: _resultConfidence,
            error: _error,
            onRetry: _start,
            onUseReading: null,
          ),
        },
      ),
    );
  }
}

class _IntroView extends StatelessWidget {
  const _IntroView({super.key, required this.onStart});
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 108,
              height: 108,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.danger, Color(0xFFE0554B)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.danger.withValues(alpha: .30),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: const Icon(
                Icons.favorite_rounded,
                size: 50,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 26),
            Text(
              'Heart rate scan',
              style: GoogleFonts.sora(
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Hold your face steady in frame in good lighting for about '
              '18 seconds. This estimates your pulse from subtle color '
              'changes in your skin.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.muted,
                height: 1.5,
                fontSize: 13.5,
              ),
            ),
            const SizedBox(height: 20),
            MCard(
              color: AppColors.soft,
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  _TipRow(
                    icon: Icons.wb_sunny_rounded,
                    text: 'Sit somewhere well-lit — natural light works best',
                  ),
                  SizedBox(height: 10),
                  _TipRow(
                    icon: Icons.center_focus_strong_rounded,
                    text: 'Keep your whole face inside the guide oval',
                  ),
                  SizedBox(height: 10),
                  _TipRow(
                    icon: Icons.pan_tool_alt_rounded,
                    text: 'Hold the phone as still as you can',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.privacy_tip_rounded,
                  size: 14,
                  color: AppColors.muted,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    'Nothing is recorded or uploaded — all processing happens on your phone.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.muted, fontSize: 11.5),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'This is an estimate, not a medical device — for irregular or '
              'concerning readings, check with a doctor.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.muted, fontSize: 11.5),
            ),
            const SizedBox(height: 26),
            PrimaryButton(
              label: 'Start scan',
              icon: Icons.videocam_rounded,
              color: AppColors.danger,
              onPressed: onStart,
            ),
          ],
        ),
      ),
    );
  }
}

class _TipRow extends StatelessWidget {
  const _TipRow({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 17, color: AppColors.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12.5,
              color: AppColors.inkSoft,
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }
}

class _ScanningView extends StatefulWidget {
  const _ScanningView({
    super.key,
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
  State<_ScanningView> createState() => _ScanningViewState();
}

class _ScanningViewState extends State<_ScanningView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final steady = widget.sampleCount >= 15;

    return Stack(
      fit: StackFit.expand,
      children: [
        // Mirror the front camera preview so the guide feels natural,
        // matching how a selfie camera normally looks to the user.
        Transform(
          alignment: Alignment.center,
          transform: Matrix4.rotationY(3.14159),
          child: CameraPreview(widget.controller),
        ),
        // Dark scrim so white text/icons stay readable over any background.
        Container(color: Colors.black.withValues(alpha: .18)),
        // Face-guide oval — helps the person frame themselves correctly
        // instead of guessing where the ROI detector expects the face.
        Center(
          child: AnimatedBuilder(
            animation: _pulseCtrl,
            builder: (context, child) {
              final scale = 1.0 + (steady ? 0.0 : _pulseCtrl.value * 0.02);
              return Transform.scale(scale: scale, child: child);
            },
            child: Container(
              width: 220,
              height: 280,
              decoration: BoxDecoration(
                shape: BoxShape.rectangle,
                borderRadius: BorderRadius.circular(140),
                border: Border.all(
                  color: steady
                      ? AppColors.success
                      : Colors.white.withValues(alpha: .85),
                  width: 3,
                ),
              ),
            ),
          ),
        ),
        Positioned(
          top: 120,
          left: 0,
          right: 0,
          child: Center(
            child: AnimatedBuilder(
              animation: _pulseCtrl,
              builder: (context, _) {
                final scale = 1.0 + _pulseCtrl.value * 0.15;
                return Transform.scale(
                  scale: scale,
                  child: Icon(
                    Icons.favorite_rounded,
                    color: AppColors.danger.withValues(alpha: .9),
                    size: 30,
                  ),
                );
              },
            ),
          ),
        ),
        Positioned(
          bottom: 48,
          left: 0,
          right: 0,
          child: Column(
            children: [
              SizedBox(
                width: 76,
                height: 76,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: widget.progress,
                      strokeWidth: 5,
                      backgroundColor: Colors.white24,
                      color: AppColors.danger,
                    ),
                    Text(
                      '${(widget.progress * 100).toInt()}%',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: .35),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  _liveStatusText(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
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
    if (widget.sampleCount < 15) {
      final reason = widget.processor?.lastRejectionReason ?? '';
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

/// Broad, general resting-heart-rate reference band — informational only.
_BpmZone _zoneFor(double bpm) {
  if (bpm < 60) return _BpmZone.low;
  if (bpm <= 100) return _BpmZone.resting;
  return _BpmZone.elevated;
}

({String label, Color color, Color soft, String hint}) _zoneStyle(
  _BpmZone zone,
) {
  switch (zone) {
    case _BpmZone.low:
      return (
        label: 'Below typical resting range',
        color: AppColors.ai,
        soft: AppColors.aiSoft,
        hint:
            'Common for well-rested or very fit people — but mention it '
            'to a doctor if you feel dizzy or unusually tired.',
      );
    case _BpmZone.resting:
      return (
        label: 'Within typical resting range',
        color: AppColors.success,
        soft: AppColors.successSoft,
        hint: 'This is a normal resting range for most adults (60–100 BPM).',
      );
    case _BpmZone.elevated:
      return (
        label: 'Above typical resting range',
        color: AppColors.warning,
        soft: AppColors.warningSoft,
        hint:
            'Could simply be recent activity, caffeine, or stress — '
            'rescan after resting a few minutes for a clearer picture.',
      );
  }
}

class _ResultView extends StatelessWidget {
  const _ResultView({
    super.key,
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
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: AppColors.warningSoft,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.error_outline_rounded,
                  size: 34,
                  color: AppColors.warning,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Couldn\'t get a reading',
                style: GoogleFonts.sora(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.muted, height: 1.4),
              ),
              const SizedBox(height: 22),
              PrimaryButton(
                label: 'Try again',
                icon: Icons.refresh_rounded,
                color: AppColors.danger,
                onPressed: onRetry,
              ),
            ],
          ),
        ),
      );
    }

    final bool validated =
        bpm != null &&
        autocorrBpm != null &&
        (bpm! - autocorrBpm!).abs() <= 3.0;
    final zone = bpm != null ? _zoneFor(bpm!) : null;
    final zoneStyle = zone != null ? _zoneStyle(zone) : null;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  (zoneStyle?.color ?? AppColors.danger),
                  (zoneStyle?.color ?? AppColors.danger).withValues(alpha: .75),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: (zoneStyle?.color ?? AppColors.danger).withValues(
                    alpha: .3,
                  ),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              children: [
                const Icon(
                  Icons.favorite_rounded,
                  color: Colors.white,
                  size: 30,
                ),
                const SizedBox(height: 8),
                Text(
                  '${bpm?.round() ?? '--'}',
                  style: GoogleFonts.sora(
                    fontSize: 58,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    height: 1.0,
                  ),
                ),
                Text(
                  'BPM',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: .85),
                    letterSpacing: 3,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          if (zoneStyle != null)
            MCard(
              color: zoneStyle.soft,
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_rounded, size: 18, color: zoneStyle.color),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          zoneStyle.label,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: zoneStyle.color,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          zoneStyle.hint,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.inkSoft,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 10),
          if (validated)
            _ConfidenceChip(
              icon: Icons.verified_rounded,
              label: 'Signal checks agree',
              color: AppColors.success,
            )
          else if (confidence != null && confidence! >= 6.0)
            _ConfidenceChip(
              icon: Icons.check_circle_outline_rounded,
              label: 'High confidence reading',
              color: AppColors.success,
            )
          else if (confidence != null)
            _ConfidenceChip(
              icon: Icons.info_outline_rounded,
              label: 'Low confidence — hold still & rescan for accuracy',
              color: AppColors.warning,
            ),
          const SizedBox(height: 16),
          Text(
            'Estimate only — not a medical diagnosis. If this feels off or '
            'you have symptoms, check with a doctor.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.muted,
              fontSize: 11.5,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 22),
          if (onUseReading != null) ...[
            PrimaryButton(
              label: 'Use this reading',
              icon: Icons.check_rounded,
              color: AppColors.danger,
              onPressed: onUseReading,
            ),
            const SizedBox(height: 10),
          ],
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Scan again'),
          ),
          if (kDebugMode && debugLog != null) ...[
            const SizedBox(height: 10),
            TextButton.icon(
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
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('Debug copied')));
                }
              },
              icon: const Icon(Icons.bug_report, size: 16),
              label: const Text('Debug details (dev only)'),
            ),
          ],
        ],
      ),
    );
  }
}

class _ConfidenceChip extends StatelessWidget {
  const _ConfidenceChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withValues(alpha: .35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
