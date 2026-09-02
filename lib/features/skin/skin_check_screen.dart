import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/services/skin_photo_quality_checker.dart';
import '../../core/services/skin_scan_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_loading.dart';
import '../../core/widgets/guest_gate.dart';
import '../../core/widgets/shared_widgets.dart';
import '../../services/skin_scan_firestore_service.dart';
import 'skin_history_screen.dart';
import 'skin_scan_camera_screen.dart';

/// Home-screen entry point for a skin check — capture, analyze, show the
/// result, and only save it to history if the user chooses to (unlike the
/// chat flow, which auto-saves every scan).
class SkinCheckScreen extends StatefulWidget {
  const SkinCheckScreen({super.key});

  @override
  State<SkinCheckScreen> createState() => _SkinCheckScreenState();
}

enum _State { idle, analyzing, done, error }

class _SkinCheckScreenState extends State<SkinCheckScreen> {
  _State _state = _State.idle;
  String? _error;
  List<SkinMetric>? _metrics;
  String? _imagePath;
  bool _saved = false;
  bool _saving = false;

  Future<void> _startScan() async {
    final path = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const SkinScanCameraScreen()),
    );
    if (path == null || !mounted) return;
    await _analyze(path);
  }

  Future<void> _pickFromGallery() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 90,
    );
    if (picked == null || !mounted) return;
    await _analyze(picked.path);
  }

  Future<void> _analyze(String path) async {
    setState(() {
      _state = _State.analyzing;
      _error = null;
      _saved = false;
    });

    try {
      final quality = await SkinPhotoQualityChecker.check(path);
      if (quality != SkinPhotoQuality.ok) {
        if (!mounted) return;
        setState(() {
          _state = _State.error;
          _error = SkinPhotoQualityChecker.message(quality);
        });
        return;
      }

      final result = await SkinScanService.analyze(path);
      if (!mounted) return;

      if (result.metrics.isEmpty) {
        setState(() {
          _state = _State.error;
          _error =
              "MedAI couldn't get a reading from that photo. Please "
              "try again with a clear, well-lit photo of your face.";
        });
        return;
      }

      setState(() {
        _state = _State.done;
        _metrics = result.metrics;
        _imagePath = path;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _state = _State.error;
        _error =
            "Couldn't complete the skin scan — the analysis server "
            "might be waking up (this can take up to a minute on the "
            "first try). Please try again.";
      });
    }
  }

  Future<void> _saveToHistory() async {
    if (_metrics == null || _saving) return;
    if (!await requireLogin(
      context,
      feature: 'save this scan to your history',
    )) {
      return;
    }
    if (!mounted) return;
    setState(() => _saving = true);
    try {
      await SkinScanFirestoreService.instance.saveScan(
        SkinScanRecord(
          metrics: {for (final m in _metrics!) m.label: m.score},
          imagePath: _imagePath,
          date: DateTime.now(),
        ),
      );
      if (mounted) setState(() => _saved = true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _reset() {
    setState(() {
      _state = _State.idle;
      _error = null;
      _metrics = null;
      _imagePath = null;
      _saved = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        backgroundColor: AppColors.paper,
        surfaceTintColor: AppColors.paper,
        title: const Text('Skin check'),
        actions: [
          IconButton(
            tooltip: 'History',
            icon: const Icon(Icons.history_rounded),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SkinHistoryScreen()),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 20.w),
          child: switch (_state) {
            _State.idle => _IntroView(
              onStart: _startScan,
              onGallery: _pickFromGallery,
            ),
            _State.analyzing => const _AnalyzingState(),
            _State.error => _ErrorView(message: _error!, onRetry: _startScan),
            _State.done => _ResultView(
              metrics: _metrics!,
              imagePath: _imagePath,
              saved: _saved,
              saving: _saving,
              onSave: _saveToHistory,
              onRescan: _reset,
            ),
          },
        ),
      ),
    );
  }
}

class _IntroView extends StatelessWidget {
  const _IntroView({required this.onStart, required this.onGallery});
  final VoidCallback onStart;
  final VoidCallback onGallery;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96.r,
              height: 96.r,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: AppColors.gradient,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.face_retouching_natural_rounded,
                color: Colors.white,
                size: 42.sp,
              ),
            ),
            SizedBox(height: 22.h),
            Text(
              'Skin check',
              style: GoogleFonts.sora(
                fontSize: 21.sp,
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
              ),
            ),
            SizedBox(height: 8.h),
            Text(
              'Take a clear, well-lit photo of your face and MedAI will '
              'give you a general visual read on skin condition — not a '
              'diagnosis.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5.sp,
                color: AppColors.muted,
                height: 1.45,
              ),
            ),
            SizedBox(height: 26.h),
            PrimaryButton(
              label: 'Start scan',
              icon: Icons.camera_alt_rounded,
              onPressed: onStart,
            ),
            SizedBox(height: 10.h),
            SecondaryButton(
              label: 'Choose from gallery',
              icon: Icons.photo_library_rounded,
              onPressed: onGallery,
            ),
            SizedBox(height: 26.h),
            MCard(
              color: AppColors.soft,
              border: Border.all(color: AppColors.primary.withValues(alpha: .18)),
              padding: EdgeInsets.all(14.r),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.lightbulb_outline_rounded,
                      color: AppColors.primaryDark, size: 20.sp),
                  SizedBox(width: 10.w),
                  Expanded(
                    child: Text(
                      'Good, even lighting and a bare face (no makeup or '
                          'filters) help MedAI read your skin more accurately.',
                      style: TextStyle(
                        fontSize: 12.sp,
                        height: 1.4,
                        color: AppColors.onSoft,
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

class _AnalyzingState extends StatelessWidget {
  const _AnalyzingState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const AppSpinner(),
          SizedBox(height: 16.h),
          Text(
            'Analyzing your photo…',
            style: TextStyle(fontSize: 14.sp, color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.error_outline_rounded,
            size: 40.sp,
            color: AppColors.danger,
          ),
          SizedBox(height: 12.h),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13.5.sp, color: AppColors.inkSoft),
          ),
          SizedBox(height: 20.h),
          PrimaryButton(label: 'Try again', onPressed: onRetry),
        ],
      ),
    );
  }
}

class _ResultView extends StatelessWidget {
  const _ResultView({
    required this.metrics,
    required this.imagePath,
    required this.saved,
    required this.saving,
    required this.onSave,
    required this.onRescan,
  });

  final List<SkinMetric> metrics;
  final String? imagePath;
  final bool saved;
  final bool saving;
  final VoidCallback onSave;
  final VoidCallback onRescan;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.symmetric(vertical: 16.h),
      children: [
        if (imagePath != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(14.r),
            child: Image.file(File(imagePath!),
                height: 170.h, width: double.infinity, fit: BoxFit.cover),
          ),
        SizedBox(height: 16.h),
        MCard(
          border: Border.all(color: AppColors.ai.withValues(alpha: .45), width: 1.w),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ReportCardHeader(
                icon: Icons.face_retouching_natural_rounded,
                title: 'Skin analysis',
                trailing: '${metrics.length} metric${metrics.length == 1 ? '' : 's'}',
              ),
              SizedBox(height: 14.h),
              for (final m in metrics)
                SkinMetricRow(label: m.label, score: m.score),
              Divider(height: 18.h),
              Text(
                'Cosmetic visual estimate — not a medical diagnosis. If '
                    'anything looks concerning, please see a dermatologist.',
                style: TextStyle(
                  fontSize: 11.5.sp,
                  fontStyle: FontStyle.italic,
                  color: AppColors.muted,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: 20.h),
        if (saved)
          Container(
            padding: EdgeInsets.symmetric(vertical: 12.h),
            decoration: BoxDecoration(
              color: AppColors.successSoft,
              borderRadius: BorderRadius.circular(12.r),
            ),
            child: Center(
              child: Text(
                'Saved to your skin history',
                style: TextStyle(
                  fontSize: 13.sp,
                  fontWeight: FontWeight.w700,
                  color: AppColors.success,
                ),
              ),
            ),
          )
        else
          PrimaryButton(
            label: saving ? 'Saving…' : 'Save to history',
            icon: Icons.bookmark_add_rounded,
            onPressed: saving ? null : onSave,
          ),
        SizedBox(height: 10.h),
        OutlinedButton.icon(
          onPressed: onRescan,
          icon: const Icon(Icons.replay_rounded),
          label: const Text('Scan again'),
        ),
      ],
    );
  }
}
