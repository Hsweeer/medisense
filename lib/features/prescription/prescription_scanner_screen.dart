import 'dart:io';

import 'package:cunning_document_scanner/cunning_document_scanner.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/services/gemini_service.dart';
import '../../core/services/image_cleaner_service.dart';
import '../../core/services/prescription_history_preferences.dart';
import '../../core/services/prescription_log_service.dart';
import '../../core/services/prescription_parser.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_loading.dart';
import '../../core/widgets/shared_widgets.dart';
import '../../data/models/prescription_models.dart';
import '../../providers/auth_provider.dart';
import '../chat/prescription_review_screen.dart';
import '../profile/prescription_history_screen.dart';

/// Home-screen entry point for scanning a prescription directly — same
/// Gemini read + parsing + professional summary used in chat, just without
/// needing to go through a chat conversation first.
class PrescriptionScannerScreen extends StatefulWidget {
  const PrescriptionScannerScreen({super.key});

  @override
  State<PrescriptionScannerScreen> createState() =>
      _PrescriptionScannerScreenState();
}

class _PrescriptionScannerScreenState extends State<PrescriptionScannerScreen> {
  bool _processing = false;
  String? _error;

  // Result state, once a scan succeeds.
  String? _summary;
  List<ParsedMedicine>? _meds;
  String? _ocrJson;
  String? _imagePath;

  Future<void> _capture(ImageSource source) async {
    if (_processing) return;

    String? imagePath;
    if (source == ImageSource.camera) {
      // Same live document scanner used for "Scan prescription" inside
      // MedAI chat — auto edge-detection, crop, and a proper scanning UI,
      // instead of the phone's plain default camera.
      try {
        final pictures = await CunningDocumentScanner.getPictures();
        if (pictures != null && pictures.isNotEmpty) {
          imagePath = pictures.first;
        }
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _error = "Could not open the document scanner. Please try again.";
        });
        return;
      }
    } else {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 90,
      );
      imagePath = picked?.path;
    }
    if (imagePath == null || !mounted) return;

    setState(() {
      _processing = true;
      _error = null;
    });

    try {
      final cleanedPath = await ImageCleanerService.cleanForVision(imagePath);
      final processPath = cleanedPath ?? imagePath;

      final jsonOutput = await GeminiService.readPrescription(processPath);
      final meds = getMedsFromOcr(jsonOutput);
      final summary = buildProfessionalSummary(meds);

      final validCount = meds.where((m) => m.name.trim().isNotEmpty).length;
      // Guests can scan and read a prescription like anyone else, but
      // there's no account to attach the Firestore history record to —
      // skip the auto-save rather than let it fail silently, or worse,
      // write under the wrong user if a real sign-in happens later in
      // the same session.
      final isGuest = mounted && context.read<AuthProvider>().isGuest;
      if (validCount > 0 &&
          !isGuest &&
          await PrescriptionHistoryPreferences.instance.isEnabled()) {
        try {
          await PrescriptionLogService.instance.save(
            PrescriptionHistoryEntry(
              summary: summary,
              medicineCount: validCount,
              scannedAt: DateTime.now(),
            ),
          );
        } catch (_) {
          // Non-fatal — result is still shown even if history save fails.
        }
      }

      if (!mounted) return;
      setState(() {
        _processing = false;
        _meds = meds;
        _summary = summary;
        _ocrJson = jsonOutput;
        _imagePath = processPath;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _processing = false;
        _error =
            "Scanning error. Please ensure the photo is clear and try again.";
      });
    }
  }

  void _rescan() {
    setState(() {
      _summary = null;
      _meds = null;
      _ocrJson = null;
      _imagePath = null;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        backgroundColor: AppColors.paper,
        surfaceTintColor: AppColors.paper,
        title: const Text('Scan prescription'),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.success,
              elevation: 0,
            ),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const PrescriptionHistoryScreen(),
              ),
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
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 20.w),
          child: _processing
              ? const _AnalyzingState()
              : _summary != null
              ? _ResultView(
                  summary: _summary!,
                  meds: _meds!,
                  ocrJson: _ocrJson!,
                  imagePath: _imagePath,
                  onRescan: _rescan,
                )
              : _IntroView(error: _error, onCapture: _capture),
        ),
      ),
    );
  }
}

class _IntroView extends StatelessWidget {
  const _IntroView({required this.onCapture, this.error});
  final void Function(ImageSource) onCapture;
  final String? error;

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
                Icons.receipt_long_rounded,
                color: Colors.white,
                size: 42.sp,
              ),
            ),
            SizedBox(height: 22.h),
            Text(
              'Scan a prescription',
              style: GoogleFonts.sora(
                fontSize: 21.sp,
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
              ),
            ),
            SizedBox(height: 8.h),
            Text(
              'Snap a photo or pick one from your gallery and MedAI will '
              'read the medicines, doses, and instructions — in English, '
              'Urdu, or Roman Urdu.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5.sp,
                color: AppColors.muted,
                height: 1.45,
              ),
            ),
            if (error != null) ...[
              SizedBox(height: 16.h),
              Container(
                padding: EdgeInsets.all(12.r),
                decoration: BoxDecoration(
                  color: AppColors.dangerSoft,
                  borderRadius: BorderRadius.circular(12.r),
                ),
                child: Text(
                  error!,
                  style: TextStyle(fontSize: 12.5.sp, color: AppColors.danger),
                ),
              ),
            ],
            SizedBox(height: 26.h),
            PrimaryButton(
              label: 'Start scan',
              icon: Icons.camera_alt_rounded,
              onPressed: () => onCapture(ImageSource.camera),
            ),
            SizedBox(height: 10.h),
            SecondaryButton(
              label: 'Choose from gallery',
              icon: Icons.photo_library_rounded,
              onPressed: () => onCapture(ImageSource.gallery),
            ),
            SizedBox(height: 26.h),
            MCard(
              color: AppColors.soft,
              border: Border.all(
                color: AppColors.primary.withValues(alpha: .18),
              ),
              padding: EdgeInsets.all(14.r),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.lightbulb_outline_rounded,
                    color: AppColors.primaryDark,
                    size: 20.sp,
                  ),
                  SizedBox(width: 10.w),
                  Expanded(
                    child: Text(
                      'Lay the prescription flat on a well-lit surface and '
                      'fit the whole page in frame for the clearest read.',
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
            'Reading your prescription…',
            style: TextStyle(fontSize: 14.sp, color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}

class _ResultView extends StatefulWidget {
  const _ResultView({
    required this.summary,
    required this.meds,
    required this.ocrJson,
    required this.imagePath,
    required this.onRescan,
  });

  final String summary;
  final List<ParsedMedicine> meds;
  final String ocrJson;
  final String? imagePath;
  final VoidCallback onRescan;

  @override
  State<_ResultView> createState() => _ResultViewState();
}

class _ResultViewState extends State<_ResultView> {
  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.symmetric(vertical: 16.h),
      children: [
        if (widget.imagePath != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(14.r),
            child: Image.file(
              File(widget.imagePath!),
              height: 140.h,
              width: double.infinity,
              fit: BoxFit.cover,
            ),
          ),
        SizedBox(height: 14.h),
        Row(
          children: [
            Expanded(
              child: Text(
                'Prescription summary',
                style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w800),
              ),
            ),
            IconButton(
              tooltip: 'Copy summary',
              icon: Icon(
                Icons.copy_rounded,
                size: 18.sp,
                color: AppColors.muted,
              ),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: widget.summary));
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('Summary copied')));
              },
            ),
          ],
        ),
        MCard(
          color: AppColors.paper,
          child: SelectableText(
            widget.summary,
            style: TextStyle(
              fontSize: 12.5.sp,
              color: AppColors.inkSoft,
              height: 1.55,
              fontFamily: 'monospace',
            ),
          ),
        ),
        SizedBox(height: 18.h),
        PrimaryButton(
          label: 'Add reminders',
          icon: Icons.alarm_add_rounded,
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => PrescriptionReviewScreen(
                ocrText: widget.ocrJson,
                initialMeds: widget.meds,
                imagePath: widget.imagePath,
              ),
            ),
          ),
        ),
        SizedBox(height: 18.h),
        OutlinedButton.icon(
          onPressed: widget.onRescan,
          icon: const Icon(Icons.replay_rounded),
          label: const Text('Scan another'),
        ),
        SizedBox(height: 8.h),
        Center(
          child: Text(
            'Automatically saved to your prescription history.',
            style: TextStyle(fontSize: 11.sp, color: AppColors.muted),
          ),
        ),
      ],
    );
  }
}
