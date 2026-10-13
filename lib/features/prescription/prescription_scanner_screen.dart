import 'dart:io';

import 'package:cunning_document_scanner/cunning_document_scanner.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/services/gemini_service.dart';
import '../../core/services/image_cleaner_service.dart';
import '../../core/services/prescription_export_service.dart';
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
      final summary = buildProfessionalSummary(
        meds,
        metadata: extractPrescriptionMetadata(jsonOutput),
      );

      // History is NOT auto-saved here. The result screen shows a
      // checkbox ("Save summary & photo to history"). When the user
      // taps "Add reminders" with that checkbox on, history is saved
      // right before navigating to the review screen.
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
  /// When checked, tapping "Add reminders" also saves summary + photo
  /// to prescription history automatically (no separate Save button).
  bool _saveToHistory = true;
  bool _busy = false;
  bool _historySaved = false;

  List<ParsedMedicine> get _validMeds =>
      widget.meds.where((m) => m.name.trim().isNotEmpty).toList();

  Future<void> _persistHistoryIfNeeded() async {
    if (!_saveToHistory || _historySaved) return;

    if (!await requireLogin(
      context,
      feature: 'save this prescription to your history',
    )) {
      return;
    }
    if (!mounted) return;

    try {
      await PrescriptionLogService.instance.save(
        PrescriptionHistoryEntry(
          summary: widget.summary,
          medicineCount: _validMeds.length,
          scannedAt: DateTime.now(),
          photoUrl: widget.imagePath,
        ),
      );
      if (mounted) setState(() => _historySaved = true);
    } catch (e) {
      debugPrint('[PrescriptionScanner] history save failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Couldn't save to history — reminders still work."),
          ),
        );
      }
    }
  }

  /// Save summary + photo to history without requiring reminders.
  /// Useful for archiving old prescriptions.
  Future<void> _onSaveToHistory() async {
    if (_busy || _historySaved) return;
    setState(() => _busy = true);
    try {
      if (!await requireLogin(
        context,
        feature: 'save this prescription to your history',
      )) {
        return;
      }
      if (!mounted) return;

      await PrescriptionLogService.instance.save(
        PrescriptionHistoryEntry(
          summary: widget.summary,
          medicineCount: _validMeds.length,
          scannedAt: DateTime.now(),
          photoUrl: widget.imagePath,
        ),
      );
      if (!mounted) return;
      setState(() => _historySaved = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Saved to prescription history'),
        ),
      );
    } catch (e) {
      debugPrint('[PrescriptionScanner] save to history failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't save — please try again.")),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _onAddReminders() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _persistHistoryIfNeeded();
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PrescriptionReviewScreen(
            ocrText: widget.ocrJson,
            initialMeds: widget.meds,
            imagePath: widget.imagePath,
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _onShare() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await showModalBottomSheet<void>(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (ctx) => _ShareSheet(
          summary: widget.summary,
          medicineCount: _validMeds.length,
          imagePath: widget.imagePath,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _onPrintPdf() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await PrescriptionExportService.instance.printPdf(
        summary: widget.summary,
        medicineCount: _validMeds.length,
        imagePath: widget.imagePath,
      );
    } catch (e) {
      debugPrint('[PrescriptionScanner] print failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Couldn't open print — please try again."),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
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
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Summary copied')),
                );
              },
            ),
          ],
        ),
        SizedBox(height: 8.h),
        Container(
          width: double.infinity,
          padding: EdgeInsets.all(16.r),
          decoration: BoxDecoration(
            color: AppColors.soft,
            borderRadius: BorderRadius.circular(14.r),
            border: Border.all(color: AppColors.primary.withValues(alpha: .12)),
          ),
          child: _FormattedSummaryText(summary: widget.summary),
        ),
        SizedBox(height: 16.h),
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

        // ── Share / Print PDF actions ──────────────────────────────────
        SizedBox(height: 18.h),
        Row(
          children: [
            Expanded(
              child: _ActionChip(
                icon: Icons.share_rounded,
                label: 'Share',
                onTap: _busy ? null : _onShare,
              ),
            ),
            SizedBox(width: 10.w),
            Expanded(
              child: _ActionChip(
                icon: Icons.picture_as_pdf_rounded,
                label: 'PDF / Print',
                onTap: _busy ? null : _onPrintPdf,
              ),
            ),
          ],
        ),

        // ── Save-to-history checkbox (replaces old Save button) ────────
        SizedBox(height: 16.h),
        Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(14.r),
            onTap: _busy || _historySaved
                ? null
                : () => setState(() => _saveToHistory = !_saveToHistory),
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
              decoration: BoxDecoration(
                color: _historySaved
                    ? AppColors.successSoft
                    : (_saveToHistory ? AppColors.soft : AppColors.card),
                borderRadius: BorderRadius.circular(14.r),
                border: Border.all(
                  color: _historySaved
                      ? AppColors.success.withValues(alpha: .35)
                      : (_saveToHistory
                      ? AppColors.primary.withValues(alpha: .28)
                      : AppColors.line),
                ),
              ),
              child: Row(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 24.r,
                    height: 24.r,
                    decoration: BoxDecoration(
                      color: _historySaved
                          ? AppColors.success
                          : (_saveToHistory
                          ? AppColors.primary
                          : Colors.transparent),
                      borderRadius: BorderRadius.circular(7.r),
                      border: Border.all(
                        color: _historySaved
                            ? AppColors.success
                            : (_saveToHistory
                            ? AppColors.primary
                            : AppColors.muted.withValues(alpha: .45)),
                        width: 1.8,
                      ),
                    ),
                    child: (_saveToHistory || _historySaved)
                        ? Icon(
                      Icons.check_rounded,
                      size: 16.sp,
                      color: Colors.white,
                    )
                        : null,
                  ),
                  SizedBox(width: 12.w),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _historySaved
                              ? 'Saved to your history'
                              : 'Save summary & photo to history',
                          style: TextStyle(
                            fontSize: 13.5.sp,
                            fontWeight: FontWeight.w700,
                            color: _historySaved
                                ? AppColors.success
                                : AppColors.ink,
                          ),
                        ),
                        SizedBox(height: 2.h),
                        Text(
                          _historySaved
                              ? 'Available under Profile → Prescription history (New / Old / All)'
                              : 'Also save when you add reminders — or use the button below',
                          style: TextStyle(
                            fontSize: 11.5.sp,
                            color: AppColors.muted,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        SizedBox(height: 18.h),
        PrimaryButton(
          label: _busy ? 'Please wait…' : 'Add reminders',
          icon: Icons.alarm_add_rounded,
          onPressed: _busy ? null : _onAddReminders,
        ),
        SizedBox(height: 10.h),
        // Standalone save — for old prescriptions or archive-only, no reminders required.
        if (_historySaved)
          Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(vertical: 14.h),
            decoration: BoxDecoration(
              color: AppColors.successSoft,
              borderRadius: BorderRadius.circular(14.r),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.check_circle_rounded, size: 18.sp, color: AppColors.success),
                SizedBox(width: 8.w),
                Text(
                  'Saved to history',
                  style: TextStyle(
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w700,
                    color: AppColors.success,
                  ),
                ),
              ],
            ),
          )
        else
          SecondaryButton(
            label: _busy ? 'Saving…' : 'Save to history only',
            icon: Icons.bookmark_add_outlined,
            onPressed: _busy ? null : _onSaveToHistory,
          ),
        SizedBox(height: 10.h),
        OutlinedButton.icon(
          onPressed: _busy ? null : widget.onRescan,
          icon: const Icon(Icons.replay_rounded),
          label: const Text('Scan another'),
        ),
        SizedBox(height: 6.h),
      ],
    );
  }
}


/// One-box summary: same single container, but headings/medicine titles
/// render bold so the text is easier to scan. No extra cards or tabs.
class _FormattedSummaryText extends StatelessWidget {
  const _FormattedSummaryText({required this.summary});
  final String summary;

  static final _medLine = RegExp(r'^\d+\.\s');
  static final _labelLine = RegExp(
    r'^(Patient|Doctor|Clinic|Diagnosis|Frequency|Duration|Instructions)\s*:',
    caseSensitive: false,
  );

  bool _isHeading(String line) {
    final t = line.trim();
    if (t.isEmpty) return false;
    if (t.toUpperCase().startsWith('PRESCRIPTION SUMMARY')) return true;
    if (t.toUpperCase() == 'NOTES' || t.toUpperCase().startsWith('NOTES ')) {
      return true;
    }
    if (t.toUpperCase().startsWith('DISCLAIMER')) return true;
    // "3 medicines identified"
    if (RegExp(r'^\d+\s+medicines?\s+identified$', caseSensitive: false)
        .hasMatch(t)) {
      return true;
    }
    return false;
  }

  bool _isMedicineTitle(String line) => _medLine.hasMatch(line.trim());

  @override
  Widget build(BuildContext context) {
    final lines = summary.split('\n');
    final base = TextStyle(
      fontSize: 12.5.sp,
      height: 1.65,
      color: AppColors.inkSoft,
      fontFamily: GoogleFonts.robotoMono().fontFamily,
    );
    final heading = base.copyWith(
      fontWeight: FontWeight.w800,
      color: AppColors.primaryDark,
      fontSize: 13.sp,
    );
    final medTitle = base.copyWith(
      fontWeight: FontWeight.w800,
      color: AppColors.ink,
    );
    final labelStyle = base.copyWith(fontWeight: FontWeight.w700);

    final spans = <TextSpan>[];
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final suffix = i < lines.length - 1 ? '\n' : '';

      if (_isHeading(line)) {
        spans.add(TextSpan(text: line + suffix, style: heading));
        continue;
      }
      if (_isMedicineTitle(line)) {
        spans.add(TextSpan(text: line + suffix, style: medTitle));
        continue;
      }

      final m = _labelLine.firstMatch(line.trim());
      if (m != null) {
        final full = line.trim();
        final label = m.group(0)!;
        final rest = full.substring(label.length);
        // preserve original leading spaces if any
        final lead = line.substring(0, line.length - line.trimLeft().length);
        spans.add(TextSpan(
          children: [
            TextSpan(text: lead + label, style: labelStyle),
            TextSpan(text: rest + suffix, style: base),
          ],
        ));
        continue;
      }

      spans.add(TextSpan(text: line + suffix, style: base));
    }

    return SelectableText.rich(
      TextSpan(children: spans),
    );
  }
}

/// Compact outlined action used for Share / PDF row.
class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(14.r),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14.r),
        child: Container(
          padding: EdgeInsets.symmetric(vertical: 13.h),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14.r),
            border: Border.all(
              color: AppColors.primary.withValues(alpha: .28),
              width: 1.4,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18.sp, color: AppColors.primary),
              SizedBox(width: 8.w),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13.5.sp,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet: Share as PDF (WhatsApp / Drive / …) or Share text + photo.
class _ShareSheet extends StatelessWidget {
  const _ShareSheet({
    required this.summary,
    required this.medicineCount,
    required this.imagePath,
  });

  final String summary;
  final int medicineCount;
  final String? imagePath;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        margin: EdgeInsets.all(12.r),
        padding: EdgeInsets.fromLTRB(16.w, 10.h, 16.w, 16.h),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22.r),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36.w,
              height: 4.h,
              decoration: BoxDecoration(
                color: AppColors.line,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            SizedBox(height: 14.h),
            Text(
              'Share prescription',
              style: GoogleFonts.sora(
                fontSize: 16.sp,
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
              ),
            ),
            SizedBox(height: 6.h),
            Text(
              'WhatsApp, email, Drive, or any app',
              style: TextStyle(fontSize: 12.sp, color: AppColors.muted),
            ),
            SizedBox(height: 16.h),
            _ShareOption(
              icon: Icons.picture_as_pdf_rounded,
              title: 'Share as PDF',
              subtitle: 'Professional document with summary & photo',
              onTap: () async {
                Navigator.of(context).pop();
                try {
                  await PrescriptionExportService.instance.sharePdf(
                    summary: summary,
                    medicineCount: medicineCount,
                    imagePath: imagePath,
                  );
                } catch (e) {
                  debugPrint('[PrescriptionScanner] share PDF failed: $e');
                }
              },
            ),
            SizedBox(height: 8.h),
            _ShareOption(
              icon: Icons.chat_rounded,
              title: 'Share text & photo',
              subtitle: 'Quick send to WhatsApp or Messages',
              onTap: () async {
                Navigator.of(context).pop();
                try {
                  await PrescriptionExportService.instance.shareTextAndPhoto(
                    summary: summary,
                    imagePath: imagePath,
                  );
                } catch (e) {
                  debugPrint('[PrescriptionScanner] share text failed: $e');
                }
              },
            ),
            SizedBox(height: 6.h),
          ],
        ),
      ),
    );
  }
}

class _ShareOption extends StatelessWidget {
  const _ShareOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.soft,
      borderRadius: BorderRadius.circular(14.r),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14.r),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
          child: Row(
            children: [
              Container(
                width: 42.r,
                height: 42.r,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12.r),
                ),
                child: Icon(icon, color: AppColors.primary, size: 22.sp),
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14.sp,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                    SizedBox(height: 2.h),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11.5.sp,
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: AppColors.muted,
                size: 22.sp,
              ),
            ],
          ),
        ),
      ),
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