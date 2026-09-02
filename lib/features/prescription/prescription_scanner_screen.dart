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
import '../../providers/profile_provider.dart';
import '../chat/prescription_review_screen.dart';

/// Home-screen entry point for scanning a prescription directly — same
/// Gemini read + parsing + professional summary used in chat, just without
/// needing to go through a chat conversation first.
class PrescriptionScannerScreen extends StatefulWidget {
  const PrescriptionScannerScreen({super.key});

  @override
  State<PrescriptionScannerScreen> createState() =>
      _PrescriptionScannerScreenState();
}

class _PrescriptionScannerScreenState
    extends State<PrescriptionScannerScreen> {
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
      final cleanedPath =
      await ImageCleanerService.cleanForVision(imagePath);
      final processPath = cleanedPath ?? imagePath;

      final jsonOutput = await GeminiService.readPrescription(processPath);
      final meds = getMedsFromOcr(jsonOutput);
      final summary = buildProfessionalSummary(meds);

      final validCount = meds.where((m) => m.name.trim().isNotEmpty).length;
      if (validCount > 0 &&
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
        _error = "Scanning error. Please ensure the photo is clear and try again.";
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
              child: Icon(Icons.receipt_long_rounded,
                  color: Colors.white, size: 42.sp),
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
              style: TextStyle(fontSize: 13.5.sp, color: AppColors.muted, height: 1.45),
            ),
            if (error != null) ...[
              SizedBox(height: 16.h),
              Container(
                padding: EdgeInsets.all(12.r),
                decoration: BoxDecoration(
                  color: AppColors.dangerSoft,
                  borderRadius: BorderRadius.circular(12.r),
                ),
                child: Text(error!,
                    style: TextStyle(fontSize: 12.5.sp, color: AppColors.danger)),
              ),
            ],
            SizedBox(height: 26.h),
            PrimaryButton(
              label: 'Take a photo',
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
          Text('Reading your prescription…',
              style: TextStyle(fontSize: 14.sp, color: AppColors.muted)),
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
  bool _showFullText = false;

  /// Simple case-insensitive substring match against the user's listed
  /// allergies — a heuristic hint only, always re-verified in the full
  /// review screen. Never blocks anything on its own.
  String? _matchingAllergy(String medName, List<String> allergies) {
    final name = medName.trim().toLowerCase();
    if (name.isEmpty) return null;
    for (final allergy in allergies) {
      final a = allergy.trim().toLowerCase();
      if (a.isEmpty) continue;
      if (name.contains(a) || a.contains(name)) return allergy;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final valid =
    widget.meds.where((m) => m.name.trim().isNotEmpty).toList();
    final allergies = context.watch<ProfileProvider>().profile.allergies;

    return ListView(
      padding: EdgeInsets.symmetric(vertical: 16.h),
      children: [
        if (widget.imagePath != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(14.r),
            child: Image.file(
              File(widget.imagePath!),
              height: 150.h,
              width: double.infinity,
              fit: BoxFit.cover,
            ),
          ),
        SizedBox(height: 16.h),
        MCard(
          border: Border.all(color: AppColors.ai.withValues(alpha: .45), width: 1.w),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ReportCardHeader(
                icon: Icons.receipt_long_rounded,
                title: 'Prescription scanned',
                trailing: '${valid.length} medicine${valid.length == 1 ? '' : 's'}',
              ),
              SizedBox(height: 14.h),
              if (valid.isEmpty)
                Text(
                  'No medicines could be confidently read from this prescription.',
                  style: TextStyle(fontSize: 12.5.sp, color: AppColors.muted),
                )
              else
                for (var i = 0; i < valid.length; i++)
                  MedicineRow(
                    index: i,
                    name: valid[i].dose.trim().isEmpty
                        ? valid[i].name.trim()
                        : '${valid[i].name.trim()} — ${valid[i].dose.trim()}',
                    detail: [
                      valid[i].timesPerDay == 1
                          ? 'Once daily'
                          : '${valid[i].timesPerDay}× daily',
                      valid[i].times.map(formatTimeOfDay).join(', '),
                      if (valid[i].durationDays != null)
                        '${valid[i].durationDays} day${valid[i].durationDays == 1 ? '' : 's'}',
                      if (valid[i].instructions.trim().isNotEmpty)
                        valid[i].instructions.trim(),
                    ].join(' · '),
                    flag: _matchingAllergy(valid[i].name, allergies) != null
                        ? 'Possible match with "${_matchingAllergy(valid[i].name, allergies)}" allergy'
                        : null,
                  ),
              Divider(height: 20.h),
              Text(
                'Generated from a scanned image — always confirm with your '
                    'prescribing doctor or pharmacist before relying on it.',
                style: TextStyle(
                  fontSize: 11.5.sp,
                  fontStyle: FontStyle.italic,
                  color: AppColors.muted,
                  height: 1.4,
                ),
              ),
              SizedBox(height: 12.h),
              GestureDetector(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => PrescriptionReviewScreen(
                      ocrText: widget.ocrJson,
                      initialMeds: widget.meds,
                      imagePath: widget.imagePath,
                    ),
                  ),
                ),
                child: Container(
                  width: double.infinity,
                  padding: EdgeInsets.symmetric(vertical: 11.h),
                  decoration: BoxDecoration(
                    color: AppColors.aiSoft,
                    borderRadius: BorderRadius.circular(11.r),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.alarm_add_rounded, size: 17.sp, color: AppColors.ai),
                      SizedBox(width: 7.w),
                      Text(
                        'Review & add reminders',
                        style: TextStyle(
                          fontSize: 12.5.sp,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ai,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: 10.h),
        GestureDetector(
          onTap: () => setState(() => _showFullText = !_showFullText),
          child: Row(
            children: [
              Icon(
                _showFullText
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
                size: 18.sp,
                color: AppColors.muted,
              ),
              SizedBox(width: 4.w),
              Text(
                _showFullText ? 'Hide full text summary' : 'View full text summary',
                style: TextStyle(
                  fontSize: 12.5.sp,
                  fontWeight: FontWeight.w600,
                  color: AppColors.muted,
                ),
              ),
              const Spacer(),
              if (_showFullText)
                IconButton(
                  tooltip: 'Copy summary',
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.copy_rounded, size: 17.sp, color: AppColors.muted),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: widget.summary));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Summary copied')),
                    );
                  },
                ),
            ],
          ),
        ),
        if (_showFullText) ...[
          SizedBox(height: 8.h),
          MCard(
            color: AppColors.paper,
            child: SelectableText(
              widget.summary,
              style: TextStyle(
                fontSize: 12.sp,
                color: AppColors.inkSoft,
                height: 1.55,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
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