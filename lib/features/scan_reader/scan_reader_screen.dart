import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/services/language_pack_manager.dart';
import '../../core/services/native_tesseract_ocr.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/shared_widgets.dart';

enum _Stage { idle, extracting, done, error }

enum _SpeechState { stopped, playing, paused }

/// Scan & Read — fully offline. Take/pick a photo of any printed text
/// (medicine label, prescription, leaflet, sign), Tesseract OCR reads the
/// text on-device (no network call), then flutter_tts reads it back aloud.
class ScanReaderScreen extends StatefulWidget {
  const ScanReaderScreen({super.key});

  @override
  State<ScanReaderScreen> createState() => _ScanReaderScreenState();
}

class _ScanReaderScreenState extends State<ScanReaderScreen> {
  final _tts = FlutterTts();
  final _picker = ImagePicker();

  File? _image;
  String _text = '';
  String _error = '';
  _Stage _stage = _Stage.idle;
  _SpeechState _speech = _SpeechState.stopped;

  @override
  void initState() {
    super.initState();
    _tts.setLanguage('en-US');
    _tts.setSpeechRate(0.48); // a bit slower than default — easier to follow
    _tts.setPitch(1.0);
    _tts.setCompletionHandler(() {
      if (mounted) setState(() => _speech = _SpeechState.stopped);
    });
    _tts.setCancelHandler(() {
      if (mounted) setState(() => _speech = _SpeechState.stopped);
    });
    _tts.setPauseHandler(() {
      if (mounted) setState(() => _speech = _SpeechState.paused);
    });
    _tts.setContinueHandler(() {
      if (mounted) setState(() => _speech = _SpeechState.playing);
    });
  }

  @override
  void dispose() {
    _tts.stop();
    super.dispose();
  }

  Future<void> _pick(ImageSource source) async {
    try {
      final picked = await _picker.pickImage(
        source: source,
        imageQuality: 90,
        // Full camera resolution (often 3000×4000px+) makes Tesseract take
        // minutes on a budget device for no accuracy benefit — OCR doesn't
        // need more than ~2200px on the long side, and this makes the
        // difference between a few seconds and multiple minutes.
        maxWidth: 2200,
        maxHeight: 2200,
      );
      if (picked == null) return; // user cancelled
      await _tts.stop();
      setState(() {
        _image = File(picked.path);
        _text = '';
        _error = '';
        _stage = _Stage.idle;
        _speech = _SpeechState.stopped;
      });
      await _extract();
    } catch (e) {
      if (!mounted) return;
      showToast(context, 'Could not open camera/gallery — check app permissions',
          color: AppColors.danger);
    }
  }

  Future<void> _extract() async {
    final image = _image;
    if (image == null) return;
    setState(() {
      _stage = _Stage.extracting;
      _error = '';
    });
    try {
      await LanguagePackManager.instance.ensureBundledEnglishReady();
      final tessdataParentPath =
          await LanguagePackManager.instance.tessdataParentDir();
      final result = await NativeTesseractOcr.extractText(
        imagePath: image.path,
        tessdataParentPath: tessdataParentPath,
        language: 'eng',
      );
      final cleaned = result.trim();
      if (!mounted) return;
      setState(() {
        _text = cleaned;
        _stage = _Stage.done;
        _error = cleaned.isEmpty ? 'No readable text was found in that photo.' : '';
      });
    } catch (e) {
      debugPrint('[ScanReader] OCR error: $e');
      if (!mounted) return;
      setState(() {
        _stage = _Stage.error;
        _error = 'Could not read text from this image. Try a clearer, '
            'well-lit, straight-on photo.';
      });
    }
  }

  Future<void> _speak() async {
    if (_text.trim().isEmpty) return;
    if (_speech == _SpeechState.paused) {
      final resumed = await _tts.speak(_text); // most platforms just replay
      if (resumed == 1 && mounted) setState(() => _speech = _SpeechState.playing);
      return;
    }
    final result = await _tts.speak(_text);
    if (result == 1 && mounted) setState(() => _speech = _SpeechState.playing);
  }

  Future<void> _pauseOrStop() async {
    if (_speech == _SpeechState.playing) {
      final result = await _tts.pause();
      if (result != 1) {
        // Some platforms don't support pause — fall back to stop.
        await _tts.stop();
        if (mounted) setState(() => _speech = _SpeechState.stopped);
      }
    } else {
      await _tts.stop();
      if (mounted) setState(() => _speech = _SpeechState.stopped);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: Column(
          children: [
            _Header(onBack: () => Navigator.of(context).pop()),
            Expanded(
              child: ListView(
                padding: EdgeInsets.fromLTRB(20.w, 8.h, 20.w, 24.h),
                children: [
                  Container(
                    padding: EdgeInsets.all(12.r),
                    decoration: BoxDecoration(
                      color: AppColors.soft,
                      borderRadius: BorderRadius.circular(14.r),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.wifi_off_rounded,
                            color: AppColors.onSoft, size: 18.sp),
                        SizedBox(width: 8.w),
                        Expanded(
                          child: Text(
                            'Works fully offline — the photo never leaves your phone.',
                            style: TextStyle(
                                fontSize: 12.sp,
                                color: AppColors.onSoft,
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 16.h),
                  _ImagePreview(image: _image, stage: _stage),
                  SizedBox(height: 14.h),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _pick(ImageSource.camera),
                          icon: Icon(Icons.photo_camera_rounded, size: 18.sp),
                          label: const Text('Take Photo'),
                          style: OutlinedButton.styleFrom(
                            padding: EdgeInsets.symmetric(vertical: 13.h),
                            side: const BorderSide(color: AppColors.primary),
                            foregroundColor: AppColors.primary,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14.r)),
                          ),
                        ),
                      ),
                      SizedBox(width: 10.w),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _pick(ImageSource.gallery),
                          icon: Icon(Icons.photo_library_rounded, size: 18.sp),
                          label: const Text('Gallery'),
                          style: OutlinedButton.styleFrom(
                            padding: EdgeInsets.symmetric(vertical: 13.h),
                            side: const BorderSide(color: AppColors.primary),
                            foregroundColor: AppColors.primary,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14.r)),
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 20.h),
                  if (_stage == _Stage.extracting) const _ExtractingCard(),
                  if (_error.isNotEmpty && _stage != _Stage.extracting)
                    _MessageCard(text: _error, isError: _stage == _Stage.error),
                  if (_stage == _Stage.done && _text.isNotEmpty) ...[
                    const SectionHeader('Extracted text'),
                    SizedBox(height: 8.h),
                    _TextResultCard(text: _text),
                    SizedBox(height: 14.h),
                    Row(
                      children: [
                        Expanded(
                          child: PrimaryButton(
                            label: _speech == _SpeechState.playing
                                ? 'Reading aloud…'
                                : _speech == _SpeechState.paused
                                    ? 'Resume reading'
                                    : 'Listen',
                            icon: _speech == _SpeechState.playing
                                ? Icons.graphic_eq_rounded
                                : Icons.volume_up_rounded,
                            onPressed: _speak,
                          ),
                        ),
                        SizedBox(width: 10.w),
                        SizedBox(
                          height: 50.h,
                          width: 50.h,
                          child: OutlinedButton(
                            onPressed: _speech == _SpeechState.stopped
                                ? null
                                : _pauseOrStop,
                            style: OutlinedButton.styleFrom(
                              padding: EdgeInsets.zero,
                              side: const BorderSide(color: AppColors.line),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14.r)),
                            ),
                            child: Icon(
                              _speech == _SpeechState.playing
                                  ? Icons.pause_rounded
                                  : Icons.stop_rounded,
                              color: AppColors.ink,
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 10.h),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: _text));
                          if (context.mounted) {
                            showToast(context, 'Text copied to clipboard');
                          }
                        },
                        icon: Icon(Icons.copy_rounded, size: 16.sp),
                        label: const Text('Copy text'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onBack});
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(8.w, 4.h, 20.w, 10.h),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_rounded, color: AppColors.ink),
          ),
          Container(
            width: 34.r,
            height: 34.r,
            decoration: BoxDecoration(
              color: AppColors.soft,
              borderRadius: BorderRadius.circular(10.r),
            ),
            child: Icon(Icons.document_scanner_rounded,
                color: AppColors.primary, size: 18.sp),
          ),
          SizedBox(width: 10.w),
          Text('Scan & Read',
              style: TextStyle(
                  fontSize: 17.sp,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink)),
        ],
      ),
    );
  }
}

class _ImagePreview extends StatelessWidget {
  const _ImagePreview({required this.image, required this.stage});
  final File? image;
  final _Stage stage;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 4 / 3,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(18.r),
          border: Border.all(color: AppColors.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: image == null
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.image_outlined, size: 40.sp, color: AppColors.muted),
                    SizedBox(height: 8.h),
                    Text('Take or choose a photo of any printed text',
                        style: TextStyle(fontSize: 13.sp, color: AppColors.muted),
                        textAlign: TextAlign.center),
                  ],
                ),
              )
            : Image.file(image!, fit: BoxFit.cover, width: double.infinity),
      ),
    );
  }
}

class _ExtractingCard extends StatelessWidget {
  const _ExtractingCard();

  @override
  Widget build(BuildContext context) {
    return MCard(
      child: Row(
        children: [
          SizedBox(
            width: 20.sp,
            height: 20.sp,
            child: const CircularProgressIndicator(
                strokeWidth: 2.4, color: AppColors.primary),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Text('Reading text from the photo…',
                style: TextStyle(fontSize: 13.5.sp, color: AppColors.inkSoft)),
          ),
        ],
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({required this.text, required this.isError});
  final String text;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final color = isError ? AppColors.danger : AppColors.warning;
    final soft = isError ? AppColors.dangerSoft : AppColors.warningSoft;
    return Container(
      padding: EdgeInsets.all(14.r),
      decoration: BoxDecoration(
        color: soft,
        borderRadius: BorderRadius.circular(14.r),
      ),
      child: Row(
        children: [
          Icon(isError ? Icons.error_outline_rounded : Icons.info_outline_rounded,
              color: color, size: 18.sp),
          SizedBox(width: 10.w),
          Expanded(
            child: Text(text,
                style: TextStyle(
                    fontSize: 13.sp, color: color, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

class _TextResultCard extends StatelessWidget {
  const _TextResultCard({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return MCard(
      child: SelectableText(
        text,
        style: TextStyle(
            fontSize: 14.sp, color: AppColors.ink, height: 1.5),
      ),
    );
  }
}