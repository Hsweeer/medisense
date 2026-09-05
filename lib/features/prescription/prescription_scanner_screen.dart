import 'dart:io';

import 'package:cunning_document_scanner/cunning_document_scanner.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/services/gemini_service.dart';
import '../../core/services/image_cleaner_service.dart';
import '../../core/services/prescription_log_service.dart';
import '../../core/services/prescription_parser.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_loading.dart';
import '../../core/widgets/guest_gate.dart';
import '../../core/widgets/shared_widgets.dart';
import '../../data/models/prescription_models.dart';
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

      // NOTE: saving to history now happens explicitly from the "Save
      // summary & photo" button on the result screen below — not
      // silently here. That way the person can see and confirm exactly
      // what gets saved (and it isn't lost if the save were to fail
      // silently in the background before they ever see the result).
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
          IconButton(
            tooltip: 'History',
            icon: const Icon(Icons.history_rounded, color: AppColors.primary),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const PrescriptionHistoryScreen(),
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
  bool _saving = false;
  bool _saved = false;

  List<ParsedMedicine> get _validMeds =>
      widget.meds.where((m) => m.name.trim().isNotEmpty).toList();

  Future<void> _save() async {
    if (_saving || _saved) return;
    if (!await requireLogin(
      context,
      feature: 'save this prescription to your history',
    )) {
      return;
    }
    if (!mounted) return;
    setState(() => _saving = true);
    try {
      await PrescriptionLogService.instance.save(
        PrescriptionHistoryEntry(
          summary: widget.summary,
          medicineCount: _validMeds.length,
          scannedAt: DateTime.now(),
          // Stored the same way skin-scan history keeps its photo — as
          // the local file path, not uploaded to cloud storage. Good
          // enough to redisplay on this device; won't follow the
          // account to a different phone.
          photoUrl: widget.imagePath,
        ),
      );
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saved = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't save — please try again.")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final meds = _validMeds;
    final dateLabel = _formatDate(DateTime.now());

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
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Prescription summary',
                    style: GoogleFonts.sora(
                      fontSize: 17.sp,
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink,
                    ),
                  ),
                  SizedBox(height: 2.h),
                  Text(
                    '$dateLabel · ${meds.length} '
                    '${meds.length == 1 ? 'medicine' : 'medicines'} identified',
                    style: TextStyle(fontSize: 12.sp, color: AppColors.muted),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Copy summary',
              icon: Icon(
                Icons.copy_rounded,
                size: 19.sp,
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
        SizedBox(height: 8.h),
        // One clearly-structured card per medicine — a heading (name +
        // dose), then its details as separate labeled rows, instead of
        // one long monospace text block the old design used.
        for (var i = 0; i < meds.length; i++) ...[
          _MedicineCard(index: i + 1, medicine: meds[i]),
          SizedBox(height: 10.h),
        ],
        SizedBox(height: 8.h),
        Container(
          padding: EdgeInsets.all(12.r),
          decoration: BoxDecoration(
            color: AppColors.soft,
            borderRadius: BorderRadius.circular(12.r),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline_rounded,
                size: 16.sp,
                color: AppColors.primaryDark,
              ),
              SizedBox(width: 8.w),
              Expanded(
                child: Text(
                  'This summary is generated from a scanned image and may '
                  'contain reading errors — always confirm with your '
                  'prescribing doctor or pharmacist before relying on it.',
                  style: TextStyle(
                    fontSize: 11.5.sp,
                    height: 1.4,
                    color: AppColors.onSoft,
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: 20.h),
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
        SizedBox(height: 10.h),
        if (_saved)
          Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(vertical: 13.h),
            decoration: BoxDecoration(
              color: AppColors.successSoft,
              borderRadius: BorderRadius.circular(14.r),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.check_circle_rounded,
                  size: 18.sp,
                  color: AppColors.success,
                ),
                SizedBox(width: 8.w),
                Text(
                  'Saved summary & photo to history',
                  style: TextStyle(
                    fontSize: 13.5.sp,
                    fontWeight: FontWeight.w700,
                    color: AppColors.success,
                  ),
                ),
              ],
            ),
          )
        else
          SecondaryButton(
            label: _saving ? 'Saving…' : 'Save summary & photo',
            icon: Icons.bookmark_add_outlined,
            onPressed: _saving ? null : _save,
          ),
        SizedBox(height: 10.h),
        OutlinedButton.icon(
          onPressed: widget.onRescan,
          icon: const Icon(Icons.replay_rounded),
          label: const Text('Scan another'),
        ),
        SizedBox(height: 6.h),
      ],
    );
  }
}

const _monthNames = [
  '',
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// Formats a date as "Jan 5, 2026" without pulling in the `intl`
/// package — it isn't declared as a dependency in this project yet.
String _formatDate(DateTime date) =>
    '${_monthNames[date.month]} ${date.day}, ${date.year}';

/// One medicine's card in the result list — a clear heading (name +
/// dose + a low-confidence flag when relevant), then its schedule,
/// duration, and instructions as separate labeled detail rows.
class _MedicineCard extends StatelessWidget {
  const _MedicineCard({required this.index, required this.medicine});

  final int index;
  final ParsedMedicine medicine;

  String _frequencyLabel(BuildContext context) {
    final times = medicine.times.map((t) => t.format(context)).join(', ');
    final perDay = medicine.timesPerDay;
    final freq = perDay <= 1 ? 'Once daily' : '$perDay× daily';
    return times.isEmpty ? freq : '$freq ($times)';
  }

  @override
  Widget build(BuildContext context) {
    final lowConfidence = medicine.confidence.toLowerCase() != 'high';

    return MCard(
      padding: EdgeInsets.all(14.r),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 26.r,
                height: 26.r,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.soft,
                  borderRadius: BorderRadius.circular(8.r),
                ),
                child: Text(
                  '$index',
                  style: TextStyle(
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primaryDark,
                  ),
                ),
              ),
              SizedBox(width: 10.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      medicine.name,
                      style: TextStyle(
                        fontSize: 14.5.sp,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink,
                      ),
                    ),
                    if (medicine.dose.trim().isNotEmpty)
                      Padding(
                        padding: EdgeInsets.only(top: 2.h),
                        child: Text(
                          medicine.dose,
                          style: TextStyle(
                            fontSize: 12.sp,
                            color: AppColors.muted,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 12.h),
          _DetailRow(
            icon: Icons.schedule_rounded,
            label: 'Frequency',
            value: _frequencyLabel(context),
          ),
          if (medicine.durationDays != null) ...[
            SizedBox(height: 8.h),
            _DetailRow(
              icon: Icons.event_repeat_rounded,
              label: 'Duration',
              value: '${medicine.durationDays} days',
            ),
          ],
          if (medicine.instructions.trim().isNotEmpty) ...[
            SizedBox(height: 8.h),
            _DetailRow(
              icon: Icons.notes_rounded,
              label: 'Instructions',
              value: medicine.instructions,
            ),
          ],
          if (lowConfidence) ...[
            SizedBox(height: 10.h),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 7.h),
              decoration: BoxDecoration(
                color: AppColors.warningSoft,
                borderRadius: BorderRadius.circular(9.r),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 14.sp,
                    color: AppColors.warning,
                  ),
                  SizedBox(width: 6.w),
                  Expanded(
                    child: Text(
                      'Low confidence — please verify against the '
                      'original prescription.',
                      style: TextStyle(
                        fontSize: 11.sp,
                        color: AppColors.warning,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 15.sp, color: AppColors.primary),
        SizedBox(width: 8.w),
        SizedBox(
          width: 78.w,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11.5.sp,
              fontWeight: FontWeight.w700,
              color: AppColors.muted,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 12.5.sp,
              color: AppColors.inkSoft,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }
}
