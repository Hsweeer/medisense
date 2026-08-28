import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:cunning_document_scanner/cunning_document_scanner.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';

import '../../core/services/photo_quality_checker.dart';
import '../../core/services/prescription_parser.dart';
import '../../core/services/tts_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/shared_widgets.dart';
import '../../data/mock/mock_data.dart';
import '../../data/models/models.dart';
import '../../providers/chat_provider.dart';
import '../../providers/profile_provider.dart';
import '../../providers/location_provider.dart';
import '../../providers/sos_provider.dart';
import '../sos/sos_screen.dart';
import '../vitals/vitals_history_screen.dart';
import '../vitals/vitals_scan_screen.dart';
import 'medai_history_screen.dart';
import 'prescription_review_screen.dart';
import '../skin/skin_history_screen.dart';
import '../skin/skin_scan_camera_screen.dart';
import '../reminders/reminders_screen.dart';

/// MedAI — multimodal health assistant: text, image, file, and voice input,
/// with "Personal insights" replies tailored from the user's health profile.
class AiChatScreen extends StatefulWidget {
  const AiChatScreen({super.key});

  @override
  State<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends State<AiChatScreen> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  final _recorder = AudioRecorder();
  DateTime? _recordStart;
  String? _recordingPath;
  bool _initialScrollDone = false;
  bool _userIsNearBottom = true;
  int _lastMessageCount = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_updateScrollState);
  }

  void _updateScrollState() {
    if (!_scroll.hasClients) return;
    final maxScroll = _scroll.position.maxScrollExtent;
    _userIsNearBottom = maxScroll <= 0 || _scroll.offset >= maxScroll - 120;
  }

  @override
  void dispose() {
    _scroll.removeListener(_updateScrollState);
    _ctrl.dispose();
    _scroll.dispose();
    _recorder.dispose();
    super.dispose();
  }

  void _send() {
    context.read<ChatProvider>().send(_ctrl.text);
    _ctrl.clear();
  }

  /// Starts a real mic recording to a temp file on hold-down.
  Future<void> _startVoiceRecording(ChatProvider chat) async {
    try {
      final hasPermission = await _recorder.hasPermission();
      debugPrint('[VoiceRecording] mic permission granted: $hasPermission');
      if (!hasPermission) {
        if (mounted) {
          showToast(context,
              'Microphone permission is needed to record a voice note',
              color: AppColors.danger);
        }
        return;
      }
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
        ),
        path: path,
      );
      _recordingPath = path;
      _recordStart = DateTime.now();
      debugPrint('[VoiceRecording] started → $path');
      chat.startRecording();
    } catch (e, st) {
      debugPrint('[VoiceRecording] start FAILED: $e');
      debugPrint('$st');
      if (mounted) {
        showToast(context, 'Could not start recording', color: AppColors.danger);
      }
    }
  }

  /// Stops the mic recording on release, validates it actually captured
  /// audio, and sends the real file for transcription.
  Future<void> _stopVoiceRecording(ChatProvider chat) async {
    if (!chat.recording) return; // never actually started (e.g. permission denied)
    final secs = DateTime.now()
        .difference(_recordStart ?? DateTime.now())
        .inSeconds;
    String? path;
    try {
      path = await _recorder.stop();
      debugPrint('[VoiceRecording] stopped after ${secs}s → $path');
    } catch (e, st) {
      debugPrint('[VoiceRecording] stop FAILED: $e');
      debugPrint('$st');
      // fall back to the path we started recording to
    }

    final finalPath = path ?? _recordingPath;

    // A real recording is never just a few bytes — this catches taps too
    // quick to capture anything, or a recorder that silently failed to
    // write, before wasting a network call on garbage audio.
    if (finalPath != null) {
      final file = File(finalPath);
      final exists = await file.exists();
      final size = exists ? await file.length() : 0;
      debugPrint('[VoiceRecording] file exists: $exists, size: $size bytes');
      if (!exists || size < 1000) {
        if (mounted) {
          showToast(context, "That was too short — hold the mic a bit longer",
              color: AppColors.danger);
        }
        await chat.stopRecording(seconds: 0, cancelled: true);
        return;
      }
    }

    await chat.stopRecording(
        seconds: max(secs, 1), filePath: finalPath);
  }

  void _openAttachmentSheet() {
    final chat = context.read<ChatProvider>();
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(20.w, 16.h, 20.w, 14.h),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Share with MedAI',
                  style: GoogleFonts.sora(
                      fontSize: 16.sp, fontWeight: FontWeight.w700)),
              SizedBox(height: 10.h),
              _AttachRow(
                icon: Icons.add_a_photo_rounded,
                color: AppColors.primary,
                soft: AppColors.soft,
                title: 'Add a photo',
                sub: 'Take a new photo or choose one from your phone',
                onTap: () => _chooseAndStageImage(
                  chat,
                  intent: AttachmentIntent.general,
                  pickerTitle: 'Add a photo',
                ),
              ),
              _AttachRow(
                icon: Icons.description_rounded,
                color: AppColors.warning,
                soft: AppColors.warningSoft,
                title: 'Document / PDF',
                sub: 'Lab reports, medical records',
                onTap: () => _pickAndStageDocument(chat),
              ),
              _AttachRow(
                icon: Icons.receipt_long_rounded,
                color: AppColors.ai,
                soft: AppColors.aiSoft,
                title: 'Scan prescription',
                sub: 'MedAI reads the doctor\'s note & sets alarms itself',
                onTap: () => _scanPrescription(chat),
              ),
              _AttachRow(
                icon: Icons.face_retouching_natural_rounded,
                color: AppColors.ai,
                soft: AppColors.aiSoft,
                title: 'Skin check',
                sub: 'Detect a skin condition from a photo',
                onTap: () => _chooseAndStageImage(
                  chat,
                  intent: AttachmentIntent.skin,
                  pickerTitle: 'Skin check',
                ),
              ),
              _AttachRow(
                icon: Icons.favorite_rounded,
                color: AppColors.danger,
                soft: AppColors.dangerSoft,
                title: 'Heart rate scan',
                sub: '20s live camera scan for your pulse',
                onTap: () => _openVitalsScan(chat),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _scanPrescription(ChatProvider chat) async {
    // Note: Don't pop here, let _chooseAndStageImage handle it
    await _chooseAndStageImage(
      chat,
      intent: AttachmentIntent.prescription,
      pickerTitle: 'Scan prescription',
    );
  }

  /// One consistent camera-or-library choice, shared by "Add a photo",
  /// "Scan prescription", and "Skin check" — a single tap opens this, then
  /// the user picks camera or gallery. Replaces the old setup where
  /// "Camera" and "Photo library" were two separate top-level buttons, and
  /// "Scan prescription"/"Skin check" only ever opened the camera directly
  /// with no gallery option at all.
  Future<void> _chooseAndStageImage(
      ChatProvider chat, {
        required AttachmentIntent intent,
        required String pickerTitle,
      }) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(20.w, 16.h, 20.w, 14.h),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(pickerTitle,
                  style: GoogleFonts.sora(
                      fontSize: 16.sp, fontWeight: FontWeight.w700)),
              SizedBox(height: 10.h),
              _AttachRow(
                icon: Icons.photo_camera_rounded,
                color: AppColors.primary,
                soft: AppColors.soft,
                title: 'Open camera',
                sub: 'Take a new photo',
                onTap: () => Navigator.of(sheetContext).pop(ImageSource.camera),
              ),
              _AttachRow(
                icon: Icons.photo_library_rounded,
                color: AppColors.primary,
                soft: AppColors.soft,
                title: 'Choose from phone',
                sub: 'Select an existing photo',
                onTap: () => Navigator.of(sheetContext).pop(ImageSource.gallery),
              ),
            ],
          ),
        ),
      ),
    );
    if (source == null || !mounted) return; // user backed out — leave the main sheet open

    // Close the main "Share with MedAI" sheet now that a source is chosen.
    Navigator.of(context).pop();
    await Future<void>.delayed(const Duration(milliseconds: 180));
    if (!mounted) return;

    await _pickAndStage(
      chat,
      source: source,
      intent: intent,
      detail: source == ImageSource.camera ? 'Camera · JPG' : 'Photo · JPG',
    );
  }

  /// Opens the real device camera or gallery and stages whatever the user
  /// actually picks.
  Future<void> _pickAndStage(
      ChatProvider chat, {
        required ImageSource source,
        required AttachmentIntent intent,
        required String detail,
      }) async {
    try {
      String? pickedPath;

      // STEP 1: Use Document Scanner for live camera prescriptions
      if (intent == AttachmentIntent.prescription && source == ImageSource.camera) {
        final List<String>? pictures = await CunningDocumentScanner.getPictures();
        if (pictures != null && pictures.isNotEmpty) {
          pickedPath = pictures.first;
        }
      } else if (intent == AttachmentIntent.skin && source == ImageSource.camera) {
        // Live face-guide camera — gives the same "actively scanning" feel
        // as the prescription document scanner, instead of a plain shutter.
        if (!mounted) return;
        pickedPath = await Navigator.of(context).push<String>(
          MaterialPageRoute(builder: (_) => const SkinScanCameraScreen()),
        );
      } else {
        // Normal ImagePicker for gallery or non-prescription intents
        final picked = await ImagePicker().pickImage(
          source: source,
          // Prescription OCR is sensitive to compression around small
          // characters, so quality stays high — but pixel dimensions must be
          // bounded regardless, or a raw camera photo (often 3000×4000px+)
          // makes Tesseract take minutes on a budget device for no real
          // accuracy gain. 3000px on the long side is comfortably more than
          // OCR needs even for small prescription text.
          imageQuality: intent == AttachmentIntent.prescription ? 90 : 85,
          maxWidth: intent == AttachmentIntent.prescription ? 1600 : 1600,
          maxHeight: intent == AttachmentIntent.prescription ? 1600 : 1600,
        );
        pickedPath = picked?.path;
      }

      if (pickedPath == null || !mounted) return; // user cancelled

      // STEP 2: Quality Check (Only for prescriptions)
      if (intent == AttachmentIntent.prescription) {
        final quality = await PhotoQualityChecker.check(pickedPath);
        if (quality != QualityResult.ok) {
          if (mounted) {
            String msg = "Image is not clear enough";
            if (quality == QualityResult.tooDark) msg = "Photo is too dark. Try better lighting.";
            if (quality == QualityResult.tooBlurry) msg = "Photo is too blurry. Hold steady and try again.";
            if (quality == QualityResult.tooSmall) msg = "Image is too small. Move closer or use a higher-resolution photo.";
            showToast(context, msg, color: AppColors.warning);
          }
          return;
        }
      }

      final fileName = pickedPath.split(Platform.pathSeparator).last;
      chat.stageAttachment(ChatAttachment(
        type: AttachmentType.image,
        name: fileName,
        detail: detail,
        intent: intent,
        filePath: pickedPath,
      ));

      // Prescription and skin photos start processing right away — the
      // user shouldn't have to also type something and hit send.
      if (intent == AttachmentIntent.prescription || intent == AttachmentIntent.skin) {
        chat.send('');
      }
    } catch (_) {
      if (!mounted) return;
      showToast(context, 'Could not open camera/gallery — check app permissions',
          color: AppColors.danger);
    }
  }

  /// Opens the device's own file picker so the user can attach a real PDF
  /// from their phone — replaces the old placeholder that staged a fake
  /// "Lab-results-June.pdf" without ever opening anything.
  Future<void> _pickAndStageDocument(ChatProvider chat) async {
    Navigator.of(context).pop(); // close the attach sheet first
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );
      final picked = result?.files.single;
      if (picked == null || picked.path == null || !mounted) return; // cancelled
      final sizeMb = picked.size / (1024 * 1024);
      chat.stageAttachment(ChatAttachment(
        type: AttachmentType.file,
        name: picked.name,
        detail: 'PDF · ${sizeMb.toStringAsFixed(1)} MB',
        filePath: picked.path,
      ));
    } catch (_) {
      if (!mounted) return;
      showToast(context, 'Could not open file picker — check app permissions',
          color: AppColors.danger);
    }
  }

  Future<void> _openVitalsScan(ChatProvider chat) async {
    Navigator.of(context).pop(); // close the attach sheet first
    final bpm = await Navigator.of(context).push<double>(
      MaterialPageRoute(builder: (_) => const VitalsScanScreen()),
    );
    if (bpm != null) {
      await chat.sendHeartRateResult(bpm);
    }
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatProvider>();

    // Professional chat UX: open on the latest message, but never yank the
    // user away from older messages they are actively reading. We auto-scroll
    // only when a new message arrives and the user is already near the bottom.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients || chat.messages.isEmpty) return;

      final currentCount = chat.messages.length;
      final maxScroll = _scroll.position.maxScrollExtent;

      if (!_initialScrollDone) {
        _scroll.jumpTo(maxScroll);
        _initialScrollDone = true;
        _userIsNearBottom = true;
        _lastMessageCount = currentCount;
        return;
      }

      if (currentCount != _lastMessageCount) {
        _lastMessageCount = currentCount;
        if (_userIsNearBottom) {
          _scroll.animateTo(
            maxScroll,
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOut,
          );
        }
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 34.r,
              height: 34.r,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: AppColors.aiGradient),
                borderRadius: BorderRadius.circular(11.r),
              ),
              child: Icon(Icons.psychology_alt_rounded,
                  color: Colors.white, size: 20.sp),
            ),
            SizedBox(width: 10.w),
            const Flexible(
              child: Text('MedAI', overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Chat history',
            icon: Icon(Icons.history_rounded, size: 22.sp, color: AppColors.inkSoft),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const MedAiHistoryScreen()),
            ),
          ),
          // Voice replies — MedAI speaks its answers aloud (on-device TTS,
          // free, works offline) so "hold mic to talk" becomes a real
          // two-way voice conversation instead of talk-in / read-out only.
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: MChip(
              chat.voiceReplyEnabled ? 'Voice replies ON' : 'Voice replies OFF',
              icon: chat.voiceReplyEnabled
                  ? Icons.volume_up_rounded
                  : Icons.volume_off_rounded,
              background:
              chat.voiceReplyEnabled ? AppColors.aiSoft : AppColors.paper,
              foreground:
              chat.voiceReplyEnabled ? AppColors.ai : AppColors.muted,
              onTap: () {
                chat.toggleVoiceReply();
                showToast(
                    context,
                    chat.voiceReplyEnabled
                        ? "MedAI will read its replies aloud"
                        : "Voice replies off");
              },
            ),
          ),
          // "Personal insights" — the learn-from-your-data switch.
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: MChip(
              chat.learnFromData ? 'Personal insights ON' : 'Personal insights OFF',
              icon: chat.learnFromData
                  ? Icons.auto_awesome_rounded
                  : Icons.auto_awesome_outlined,
              background:
              chat.learnFromData ? AppColors.aiSoft : AppColors.paper,
              foreground:
              chat.learnFromData ? AppColors.ai : AppColors.muted,
              onTap: () {
                chat.toggleLearn();
                showToast(
                    context,
                    chat.learnFromData
                        ? 'Personal insights are on — MedAI can read your '
                        'health profile to tailor its answers'
                        : "Personal insights are off — MedAI can't access "
                        'your health profile and will give general '
                        'answers only');
              },
            ),
          ),
        ],
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusScope.of(context).unfocus(),
        child: Column(
          children: [
            Container(
              width: double.infinity,
              color: const Color(0xFFFDF3E3),
              padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 8.h),
              child: Text(
                '⚠ MedAI offers general guidance — not a diagnosis. '
                    'In an emergency, call your local emergency services.',
                style: TextStyle(
                    fontSize: 12.sp,
                    color: const Color(0xFF8A5B0B),
                    fontWeight: FontWeight.w600),
              ),
            ),
            Expanded(
              child: Stack(
                children: [
                  ListView.builder(
                    controller: _scroll,
                    padding: EdgeInsets.fromLTRB(20.w, 14.h, 20.w, 8.h),
                    itemCount: chat.messages.length +
                        (chat.typing || chat.transcribing ? 1 : 0),
                    itemBuilder: (_, i) {
                      if (i == chat.messages.length) {
                        return chat.transcribing
                            ? const _TypingBubble(label: 'Transcribing voice note…')
                            : const _TypingBubble();
                      }
                      return _MessageBubble(message: chat.messages[i]);
                    },
                  ),
                  if (chat.recording) const _RecordingOverlay(),
                ],
              ),
            ),
            SizedBox(
              height: 40.h,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.symmetric(horizontal: 20.w),
                children: [
                  for (final s in MockData.aiSuggestions)
                    Padding(
                      padding: EdgeInsets.only(right: 8.w),
                      child: MChip(s,
                          background: AppColors.aiSoft,
                          foreground: AppColors.ai,
                          onTap: () => context.read<ChatProvider>().send(s)),
                    ),
                ],
              ),
            ),
            // Staged attachments preview strip.
            if (chat.pendingAttachments.isNotEmpty)
              Container(
                height: 54.h,
                padding: EdgeInsets.symmetric(horizontal: 20.w),
                alignment: Alignment.centerLeft,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final a in chat.pendingAttachments)
                      Container(
                        margin: EdgeInsets.only(right: 8.w, top: 8.h),
                        padding: EdgeInsets.symmetric(horizontal: 10.w),
                        decoration: BoxDecoration(
                          color: AppColors.soft,
                          borderRadius: BorderRadius.circular(12.r),
                        ),
                        child: Row(
                          children: [
                            Icon(
                                a.type == AttachmentType.image
                                    ? Icons.image_rounded
                                    : Icons.description_rounded,
                                size: 16.sp,
                                color: AppColors.onSoft),
                            SizedBox(width: 6.w),
                            Text(a.name,
                                style: TextStyle(
                                    fontSize: 12.sp,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.onSoft)),
                            SizedBox(width: 6.w),
                            GestureDetector(
                              onTap: () => chat.removeStaged(a),
                              child: Icon(Icons.close_rounded,
                                  size: 15.sp, color: AppColors.onSoft),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(20.w, 8.h, 20.w, 12.h),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: _openAttachmentSheet,
                      child: Container(
                        width: 46.r,
                        height: 46.r,
                        decoration: BoxDecoration(
                          color: AppColors.card,
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.line),
                        ),
                        child: Icon(Icons.add_rounded,
                            color: AppColors.inkSoft, size: 24.sp),
                      ),
                    ),
                    SizedBox(width: 8.w),
                    Expanded(
                      child: TextField(
                        controller: _ctrl,
                        style: TextStyle(fontSize: 15.sp),
                        decoration: InputDecoration(
                            hintText: 'Ask MedAI anything…',
                            hintStyle: TextStyle(fontSize: 14.sp)),
                        onSubmitted: (_) => _send(),
                      ),
                    ),
                    SizedBox(width: 8.w),
                    // Hold to record a voice note.
                    GestureDetector(
                      onLongPressStart: (_) => _startVoiceRecording(chat),
                      onLongPressEnd: (_) => _stopVoiceRecording(chat),
                      onTap: () => showToast(
                          context, 'Hold the mic to record a voice note'),
                      child: Container(
                        width: 46.r,
                        height: 46.r,
                        decoration: BoxDecoration(
                          color: chat.recording
                              ? AppColors.danger
                              : AppColors.card,
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: chat.recording
                                  ? AppColors.danger
                                  : AppColors.line),
                        ),
                        child: Icon(Icons.mic_rounded,
                            size: 24.sp,
                            color: chat.recording
                                ? Colors.white
                                : AppColors.inkSoft),
                      ),
                    ),
                    SizedBox(width: 8.w),
                    GestureDetector(
                      onTap: _send,
                      child: Container(
                        width: 46.r,
                        height: 46.r,
                        decoration: const BoxDecoration(
                          gradient:
                          LinearGradient(colors: AppColors.aiGradient),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.send_rounded,
                            color: Colors.white, size: 21.sp),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Lean, dense attachment option row.
class _AttachRow extends StatelessWidget {
  const _AttachRow({
    required this.icon,
    required this.color,
    required this.soft,
    required this.title,
    required this.sub,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final Color soft;
  final String title;
  final String sub;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 7.h),
        child: Row(
          children: [
            Container(
              width: 36.r,
              height: 36.r,
              decoration: BoxDecoration(
                  color: soft, borderRadius: BorderRadius.circular(11.r)),
              child: Icon(icon, color: color, size: 19.sp),
            ),
            SizedBox(width: 12.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontSize: 13.5.sp, fontWeight: FontWeight.w700)),
                  Text(sub,
                      style: TextStyle(
                          fontSize: 11.5.sp, color: AppColors.muted)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                size: 18.sp, color: AppColors.muted),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == ChatRole.user;

    // Red-flag → full-width SOS escalation card.
    if (message.card == ChatCardType.sos) {
      return Padding(
        padding: EdgeInsets.only(bottom: 12.h),
        child: MCard(
          color: AppColors.dangerSoft,
          border: Border.all(color: AppColors.danger, width: 1.4.w),
          onTap: () {
            final loc = context.read<LocationProvider>().position;
            final contacts = context.read<ProfileProvider>().contacts;
            context.read<SosProvider>().trigger(loc, contacts);
            Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const SosScreen()));
          },
          child: Row(
            children: [
              Container(
                width: 46.r,
                height: 46.r,
                decoration: const BoxDecoration(
                    color: AppColors.danger, shape: BoxShape.circle),
                child: Icon(Icons.sos_rounded,
                    color: Colors.white, size: 26.sp),
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('This may be an emergency',
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15.sp,
                            color: AppColors.danger)),
                    SizedBox(height: 2.h),
                    Text(message.text,
                        style: TextStyle(
                            fontSize: 12.5.sp, color: AppColors.inkSoft)),
                    SizedBox(height: 4.h),
                    Text('TAP TO OPEN EMERGENCY SOS →',
                        style: TextStyle(
                            fontSize: 11.5.sp,
                            fontWeight: FontWeight.w700,
                            color: AppColors.danger)),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Prescription scanned → structured card with auto-added reminders.
    if (message.card == ChatCardType.prescription) {
      return _PrescriptionCard(message: message);
    }

    // Heart-rate scan → structured result card with zone classification.
    if (message.card == ChatCardType.heartRate) {
      return _HeartRateCard(message: message);
    }

    // Skin check → condition-probability analysis card.
    if (message.card == ChatCardType.skin) {
      return _SkinReportCard(message: message);
    }

    // AI directly set a reminder (via chat/voice) → tap-through card.
    if (message.card == ChatCardType.reminderAdded) {
      return _ReminderAddedCard(message: message);
    }

    // AI needs more info (usually reminder time/frequency) → tappable options.
    if (message.card == ChatCardType.quickReplies) {
      return _QuickReplyCard(message: message);
    }

    final voice = message.attachments
        .where((a) => a.type == AttachmentType.voice)
        .toList();
    final media = message.attachments
        .where((a) => a.type != AttachmentType.voice)
        .toList();

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.only(bottom: 10.h),
        constraints:
        BoxConstraints(maxWidth: MediaQuery.of(context).size.width * .8),
        child: Column(
          crossAxisAlignment:
          isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            // Attachment previews above the bubble.
            for (final a in media) _AttachmentTile(attachment: a),
            for (final a in voice) _VoiceBubble(attachment: a),
            if (message.text.isNotEmpty)
              Container(
                padding:
                EdgeInsets.symmetric(horizontal: 15.w, vertical: 11.h),
                decoration: BoxDecoration(
                  color: isUser ? AppColors.primary : Colors.white,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(18.r),
                    topRight: Radius.circular(18.r),
                    bottomLeft: Radius.circular(isUser ? 18.r : 6.r),
                    bottomRight: Radius.circular(isUser ? 6.r : 18.r),
                  ),
                  border:
                  isUser ? null : Border.all(color: AppColors.line),
                ),
                child: Text.rich(
                  TextSpan(
                    text: message.text,
                    children: [
                      // Live streaming cursor — small "▍" that blinks the
                      // reply into existence token-by-token instead of
                      // popping in all at once after a long wait.
                      if (!isUser && message.streaming)
                        const TextSpan(text: ' ▍', style: TextStyle(color: AppColors.ai)),
                    ],
                  ),
                  style: TextStyle(
                      fontSize: 14.sp,
                      height: 1.45,
                      color: isUser ? Colors.white : AppColors.ink),
                ),
              ),
            if (!isUser && message.personalized)
              Padding(
                padding: EdgeInsets.only(top: 4.h),
                child: const MChip('Tailored to your health profile',
                    icon: Icons.auto_awesome_rounded,
                    background: AppColors.aiSoft,
                    foreground: AppColors.ai),
              ),
            // Tap to hear any reply read aloud — independent of the
            // "Voice replies" auto-speak toggle, so older messages in the
            // conversation stay listenable even if auto-speak is off.
            if (!isUser && message.text.isNotEmpty && !message.streaming)
              Padding(
                padding: EdgeInsets.only(top: 2.h),
                child: InkWell(
                  borderRadius: BorderRadius.circular(20.r),
                  onTap: () => TtsService.instance.speak(message.text),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                        horizontal: 6.w, vertical: 4.h),
                    child: Icon(Icons.volume_up_rounded,
                        size: 16.sp, color: AppColors.muted),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AttachmentTile extends StatelessWidget {
  const _AttachmentTile({required this.attachment});

  final ChatAttachment attachment;

  @override
  Widget build(BuildContext context) {
    if (attachment.type == AttachmentType.image) {
      final file = attachment.filePath != null ? File(attachment.filePath!) : null;
      final hasRealImage = file != null && file.existsSync();

      return GestureDetector(
        onTap: hasRealImage
            ? () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => _ImagePreviewScreen(path: file.path),
          ),
        )
            : null,
        child: Container(
          width: 190.w,
          height: 120.h,
          margin: EdgeInsets.only(bottom: 6.h),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16.r),
            color: AppColors.paper,
            border: Border.all(color: AppColors.line),
          ),
          clipBehavior: Clip.antiAlias,
          child: hasRealImage
              ? Image.file(
            file,
            fit: BoxFit.cover,
            width: 190.w,
            height: 120.h,
            errorBuilder: (_, _, _) => const _AttachmentPlaceholder(),
          )
              : const _AttachmentPlaceholder(),
        ),
      );
    }

    return Container(
      margin: EdgeInsets.only(bottom: 6.h),
      padding: EdgeInsets.all(12.r),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 38.r,
            height: 38.r,
            decoration: BoxDecoration(
                color: AppColors.warningSoft,
                borderRadius: BorderRadius.circular(11.r)),
            child: Icon(Icons.description_rounded,
                color: AppColors.warning, size: 20.sp),
          ),
          SizedBox(width: 10.w),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(attachment.name,
                  style: TextStyle(
                      fontSize: 13.sp, fontWeight: FontWeight.w700)),
              Text(attachment.detail,
                  style: TextStyle(
                      fontSize: 11.sp, color: AppColors.muted)),
            ],
          ),
        ],
      ),
    );
  }
}

class _AttachmentPlaceholder extends StatelessWidget {
  const _AttachmentPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFD8E8E4), Color(0xFFBFD9D2)],
              ),
            ),
          ),
        ),
        Center(
          child: Icon(Icons.image_rounded, size: 38.sp, color: Colors.white),
        ),
      ],
    );
  }
}

class _ImagePreviewScreen extends StatelessWidget {
  const _ImagePreviewScreen({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 1,
          maxScale: 4,
          child: Image.file(
            File(path),
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }
}

class _VoiceBubble extends StatefulWidget {
  const _VoiceBubble({required this.attachment});

  final ChatAttachment attachment;

  @override
  State<_VoiceBubble> createState() => _VoiceBubbleState();
}

class _VoiceBubbleState extends State<_VoiceBubble> {
  final _player = AudioPlayer();
  bool _playing = false;
  bool _loading = false;
  Duration _position = Duration.zero;
  late Duration _total =
  Duration(seconds: widget.attachment.durationSeconds);
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<Duration>? _durSub;
  StreamSubscription<void>? _completeSub;

  @override
  void initState() {
    super.initState();
    _posSub = _player.onPositionChanged.listen((p) {
      if (mounted) setState(() => _position = p);
    });
    _durSub = _player.onDurationChanged.listen((d) {
      if (mounted && d > Duration.zero) setState(() => _total = d);
    });
    _completeSub = _player.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          _playing = false;
          _position = Duration.zero;
        });
      }
    });
  }

  Future<void> _toggle() async {
    final path = widget.attachment.filePath;
    if (path == null) {
      showToast(context, 'This voice note has no audio to play',
          color: AppColors.danger);
      return;
    }
    if (_playing) {
      await _player.pause();
      if (mounted) setState(() => _playing = false);
      return;
    }
    setState(() => _loading = true);
    try {
      await _player.play(DeviceFileSource(path));
      if (mounted) setState(() => _playing = true);
    } catch (_) {
      if (mounted) {
        showToast(context, 'Could not play this voice note',
            color: AppColors.danger);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _fmt(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  void dispose() {
    _posSub?.cancel();
    _durSub?.cancel();
    _completeSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rng = Random(widget.attachment.durationSeconds);
    final progress = _total.inMilliseconds == 0
        ? 0.0
        : (_position.inMilliseconds / _total.inMilliseconds).clamp(0.0, 1.0);
    final litBars = (progress * 22).round();

    return GestureDetector(
      onTap: _toggle,
      child: Container(
        margin: EdgeInsets.only(bottom: 6.h),
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
        decoration: BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(18.r),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _loading
                ? SizedBox(
                width: 24.sp,
                height: 24.sp,
                child: CircularProgressIndicator(
                    strokeWidth: 2.2, color: Colors.white))
                : Icon(
              _playing
                  ? Icons.pause_rounded
                  : Icons.play_arrow_rounded,
              color: Colors.white,
              size: 24.sp,
            ),
            SizedBox(width: 6.w),
            Row(
              children: [
                for (var i = 0; i < 22; i++)
                  Container(
                    width: 2.6.w,
                    height: (6 + rng.nextDouble() * 16).h,
                    margin: EdgeInsets.symmetric(horizontal: 1.1.w),
                    decoration: BoxDecoration(
                      color: Colors.white
                          .withValues(alpha: i < litBars ? 1 : .45),
                      borderRadius: BorderRadius.circular(2.r),
                    ),
                  ),
              ],
            ),
            SizedBox(width: 8.w),
            Text(
                _playing || _position > Duration.zero
                    ? _fmt(_position)
                    : widget.attachment.detail,
                style: TextStyle(
                    fontSize: 12.sp,
                    color: Colors.white,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

class _RecordingOverlay extends StatefulWidget {
  const _RecordingOverlay();

  @override
  State<_RecordingOverlay> createState() => _RecordingOverlayState();
}

class _RecordingOverlayState extends State<_RecordingOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _wave = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900))
    ..repeat(reverse: true);
  int _seconds = 0;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _seconds++);
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _wave.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: .35),
        alignment: Alignment.center,
        child: Container(
          padding: EdgeInsets.all(24.r),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24.r),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedBuilder(
                animation: _wave,
                builder: (_, child) {
                  final rng = Random(_seconds);
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < 18; i++)
                        Container(
                          width: 3.4.w,
                          height: (8 +
                              rng.nextDouble() * 26 * (.4 + _wave.value * .6)).h,
                          margin:
                          EdgeInsets.symmetric(horizontal: 1.6.w),
                          decoration: BoxDecoration(
                            color: AppColors.danger,
                            borderRadius: BorderRadius.circular(2.r),
                          ),
                        ),
                    ],
                  );
                },
              ),
              SizedBox(height: 12.h),
              Text(
                  'Recording… 0:${_seconds.toString().padLeft(2, '0')}',
                  style: TextStyle(
                      fontSize: 14.sp, fontWeight: FontWeight.w700)),
              SizedBox(height: 4.h),
              Text('Release to send',
                  style:
                  TextStyle(fontSize: 12.sp, color: AppColors.muted)),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Prescription scanned" — med rows with add/flag status and a shortcut
/// into the reminders the AI just created.
class _PrescriptionCard extends StatelessWidget {
  const _PrescriptionCard({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final meds = getMedsFromOcr(message.ocrText ?? '');
    final allergies = context.watch<ProfileProvider>().profile.allergies;

    return Padding(
      padding: EdgeInsets.only(bottom: 12.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MCard(
            border: Border.all(color: AppColors.ai.withValues(alpha: .45), width: 1.w),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 34.r,
                      height: 34.r,
                      decoration: BoxDecoration(
                          color: AppColors.aiSoft,
                          borderRadius: BorderRadius.circular(10.r)),
                      child: Icon(Icons.receipt_long_rounded,
                          color: AppColors.ai, size: 19.sp),
                    ),
                    SizedBox(width: 10.w),
                    Expanded(
                      child: Text('Prescription scanned',
                          style: TextStyle(
                              fontSize: 14.5.sp, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
                SizedBox(height: 12.h),
                for (final med in meds)
                  _MedRow(
                    name: med.dose.isEmpty ? med.name : '${med.name} ${med.dose}',
                    freq: '${med.timesPerDay}× daily'
                        '${med.durationDays != null ? ' · ${med.durationDays} days' : ''}'
                        '${med.instructions.isNotEmpty ? ' · ${med.instructions}' : ''}',
                    added: false,
                    flag: _matchingAllergy(med.name, allergies) != null
                        ? 'Possible match with "${_matchingAllergy(med.name, allergies)}" allergy'
                        : null,
                  ),
                Divider(height: 20.h),
                Text(message.text,
                    style: TextStyle(
                        fontSize: 13.sp, height: 1.45, color: AppColors.ink)),
                SizedBox(height: 12.h),
                GestureDetector(
                  onTap: () async {
                    final count = await Navigator.of(context).push<int>(
                      MaterialPageRoute(
                        builder: (_) => PrescriptionReviewScreen(
                          ocrText: message.ocrText ?? '',
                          initialMeds: meds,
                          imagePath: message.imagePath,
                        ),
                      ),
                    );
                    if (count != null && count > 0 && context.mounted) {
                      context.read<ChatProvider>().noteRemindersAdded(count);
                    }
                  },
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
                        Icon(Icons.alarm_add_rounded,
                            size: 17.sp, color: AppColors.ai),
                        SizedBox(width: 7.w),
                        Text('Review & add reminders',
                            style: TextStyle(
                                fontSize: 12.5.sp,
                                fontWeight: FontWeight.w700,
                                color: AppColors.ai)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (message.personalized)
            Padding(
              padding: EdgeInsets.only(top: 4.h),
              child: const MChip('Tailored to your health profile',
                  icon: Icons.auto_awesome_rounded,
                  background: AppColors.aiSoft,
                  foreground: AppColors.ai),
            ),
        ],
      ),
    );
  }

  /// Simple case-insensitive substring match against the user's listed
  /// allergies — a heuristic hint only, shown again (with more detail) in
  /// the full review screen. Never blocks anything on its own.
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
}

class _MedRow extends StatelessWidget {
  const _MedRow(
      {required this.name,
        required this.freq,
        required this.added,
        this.flag});

  final String name;
  final String freq;
  final bool added;
  final String? flag;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: 8.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(added ? Icons.alarm_on_rounded : Icons.warning_amber_rounded,
              size: 17.sp,
              color: added ? AppColors.success : AppColors.warning),
          SizedBox(width: 8.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: TextStyle(
                        fontSize: 13.sp, fontWeight: FontWeight.w700)),
                Text(freq,
                    style: TextStyle(
                        fontSize: 11.5.sp, color: AppColors.muted)),
                if (flag != null)
                  Text(flag!,
                      style: TextStyle(
                          fontSize: 11.5.sp,
                          fontWeight: FontWeight.w600,
                          color: AppColors.warning)),
              ],
            ),
          ),
          Text(added ? 'Reminder set' : 'Not added',
              style: TextStyle(
                  fontSize: 11.sp,
                  fontWeight: FontWeight.w700,
                  color: added ? AppColors.success : AppColors.warning)),
        ],
      ),
    );
  }
}

/// Skin analysis — condition likelihood bars + care guidance.
class _HeartRateCard extends StatelessWidget {
  const _HeartRateCard({required this.message});

  final ChatMessage message;

  _HeartRateSummary _parseSummary() {
    final text = message.text;
    final bpmMatch = RegExp(r'(\d{2,3})\s*BPM').firstMatch(text);
    final bpm = bpmMatch != null
        ? (double.tryParse(bpmMatch.group(1)!) ?? 0.0)
        : 0.0;
    final zoneMatch = RegExp(
      r'(Below typical resting range|Normal resting range|Above typical resting range)',
    ).firstMatch(text);
    final zoneLabel = zoneMatch?.group(1) ?? HeartRateReading.zoneLabelForBpm(bpm);
    final contextLine = text
        .split('\n')
        .firstWhere(
          (line) => line.contains('Aapki age') || line.contains('lower than typical') || line.contains('higher than typical') || line.contains('This estimate'),
      orElse: () => 'Estimated from camera — not a medical device',
    );
    final disclaimer = text.contains('Estimated from camera')
        ? 'Estimated from camera — not a medical device'
        : 'Estimated from camera — not a medical device';
    return _HeartRateSummary(
      bpm: bpm,
      zoneLabel: zoneLabel,
      contextLine: contextLine,
      disclaimer: disclaimer,
    );
  }

  @override
  Widget build(BuildContext context) {
    final summary = _parseSummary();
    final zone = HeartRateReading.classify(summary.bpm);
    final accent = switch (zone) {
      HeartRateZone.belowTypical => AppColors.warning,
      HeartRateZone.normal => AppColors.success,
      HeartRateZone.aboveTypical => AppColors.danger,
    };
    final soft = switch (zone) {
      HeartRateZone.belowTypical => AppColors.warningSoft,
      HeartRateZone.normal => AppColors.successSoft,
      HeartRateZone.aboveTypical => AppColors.dangerSoft,
    };

    return Padding(
      padding: EdgeInsets.only(bottom: 12.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MCard(
            border: Border.all(color: accent.withValues(alpha: .38), width: 1.w),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 34.r,
                      height: 34.r,
                      decoration: BoxDecoration(
                        color: soft,
                        borderRadius: BorderRadius.circular(10.r),
                      ),
                      child: Icon(Icons.favorite_rounded, color: accent, size: 18.sp),
                    ),
                    SizedBox(width: 10.w),
                    Expanded(
                      child: Text('Heart rate', style: TextStyle(fontSize: 14.5.sp, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
                SizedBox(height: 14.h),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(summary.bpm.toStringAsFixed(0), style: TextStyle(fontSize: 34.sp, fontWeight: FontWeight.w800, color: AppColors.ink)),
                    SizedBox(width: 8.w),
                    Padding(
                      padding: EdgeInsets.only(bottom: 8.h),
                      child: Text('BPM', style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w700, color: AppColors.muted)),
                    ),
                  ],
                ),
                SizedBox(height: 10.h),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
                  decoration: BoxDecoration(
                    color: soft,
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.brightness_1_rounded, color: accent, size: 12.sp),
                      SizedBox(width: 8.w),
                      Expanded(
                        child: Text(
                          summary.zoneLabel,
                          style: TextStyle(
                            fontSize: 12.5.sp,
                            fontWeight: FontWeight.w700,
                            color: accent,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 12.h),
                Text(
                  summary.contextLine,
                  style: TextStyle(fontSize: 12.5.sp, height: 1.45, color: AppColors.inkSoft),
                ),
                SizedBox(height: 10.h),
                Text(
                  summary.disclaimer,
                  style: TextStyle(fontSize: 11.sp, fontStyle: FontStyle.italic, color: AppColors.muted),
                ),
                SizedBox(height: 12.h),
                GestureDetector(
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const VitalsHistoryScreen())),
                  child: Container(
                    width: double.infinity,
                    padding: EdgeInsets.symmetric(vertical: 11.h),
                    decoration: BoxDecoration(
                      color: soft,
                      borderRadius: BorderRadius.circular(11.r),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.timeline_rounded, size: 17.sp, color: accent),
                        SizedBox(width: 7.w),
                        Text('View trend', style: TextStyle(fontSize: 12.5.sp, fontWeight: FontWeight.w700, color: accent)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (message.personalized)
            Padding(
              padding: EdgeInsets.only(top: 4.h),
              child: const MChip('Tailored to your health profile',
                  icon: Icons.auto_awesome_rounded,
                  background: AppColors.aiSoft,
                  foreground: AppColors.ai),
            ),
        ],
      ),
    );
  }
}

class _HeartRateSummary {
  const _HeartRateSummary({
    required this.bpm,
    required this.zoneLabel,
    required this.contextLine,
    required this.disclaimer,
  });

  final double bpm;
  final String zoneLabel;
  final String contextLine;
  final String disclaimer;
}

class _SkinReportCard extends StatelessWidget {
  const _SkinReportCard({required this.message});

  final ChatMessage message;

  /// Parses the real server response stored on the message. Returns an
  /// empty list if there's nothing to show (shouldn't normally happen,
  /// since chat_provider only sets this card when metrics exist).
  List<(String, double)> _parseMetrics() {
    final raw = message.skinScanJson;
    if (raw == null || raw.isEmpty) return [];
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final list = (data['metrics'] as List?) ?? [];
      return list
          .map((m) => (
      (m['label'] ?? '').toString(),
      ((m['score'] ?? 0) as num).toDouble(),
      ))
          .where((m) => m.$1.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    final metrics = _parseMetrics();

    return Padding(
      padding: EdgeInsets.only(bottom: 12.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MCard(
            border: Border.all(color: AppColors.ai.withValues(alpha: .45), width: 1.w),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 34.r,
                      height: 34.r,
                      decoration: BoxDecoration(
                          color: AppColors.aiSoft,
                          borderRadius: BorderRadius.circular(10.r)),
                      child: Icon(
                          Icons.face_retouching_natural_rounded,
                          color: AppColors.ai,
                          size: 19.sp),
                    ),
                    SizedBox(width: 10.w),
                    Expanded(
                      child: Text('Skin analysis',
                          style: TextStyle(
                              fontSize: 14.5.sp, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
                SizedBox(height: 12.h),
                if (metrics.isEmpty)
                  Text('No details available for this scan.',
                      style: TextStyle(fontSize: 12.5.sp, color: AppColors.muted))
                else
                  for (final m in metrics)
                    Padding(
                      padding: EdgeInsets.only(bottom: 8.h),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(m.$1,
                                    style: TextStyle(
                                        fontSize: 12.5.sp,
                                        fontWeight: FontWeight.w600)),
                              ),
                              Text('${(m.$2 * 100).round()}%',
                                  style: TextStyle(
                                      fontSize: 12.sp,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.ai)),
                            ],
                          ),
                          SizedBox(height: 4.h),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4.r),
                            child: LinearProgressIndicator(
                              value: m.$2,
                              minHeight: 6.h,
                              backgroundColor: AppColors.paper,
                              color: AppColors.ai,
                            ),
                          ),
                        ],
                      ),
                    ),
                Divider(height: 18.h),
                Text(message.text,
                    style: TextStyle(
                        fontSize: 13.sp, height: 1.45, color: AppColors.ink)),
                SizedBox(height: 12.h),
                GestureDetector(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SkinHistoryScreen()),
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
                        Icon(Icons.timeline_rounded, size: 17.sp, color: AppColors.ai),
                        SizedBox(width: 7.w),
                        Text('View scan history',
                            style: TextStyle(
                                fontSize: 12.5.sp,
                                fontWeight: FontWeight.w700,
                                color: AppColors.ai)),
                      ],
                    ),
                  ),
                ),
                SizedBox(height: 10.h),
                Text('Cosmetic visual estimate — not a medical diagnosis.',
                    style: TextStyle(
                        fontSize: 11.sp,
                        fontStyle: FontStyle.italic,
                        color: AppColors.muted)),
              ],
            ),
          ),
          if (message.personalized)
            Padding(
              padding: EdgeInsets.only(top: 4.h),
              child: const MChip('Tailored to your health profile',
                  icon: Icons.auto_awesome_rounded,
                  background: AppColors.aiSoft,
                  foreground: AppColors.ai),
            ),
        ],
      ),
    );
  }
}

/// Shown right in the chat when MedAI directly sets a reminder from a
/// conversation (text or voice) — confirms what was set and lets the user
/// tap through to see/edit it on the real Reminders screen.
class _ReminderAddedCard extends StatelessWidget {
  const _ReminderAddedCard({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: 12.h),
      child: GestureDetector(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const RemindersScreen()),
        ),
        child: MCard(
          border: Border.all(color: AppColors.ai.withValues(alpha: .45), width: 1.w),
          child: Row(
            children: [
              Container(
                width: 34.r,
                height: 34.r,
                decoration: BoxDecoration(
                    color: AppColors.aiSoft,
                    borderRadius: BorderRadius.circular(10.r)),
                child: Icon(Icons.alarm_add_rounded, color: AppColors.ai, size: 19.sp),
              ),
              SizedBox(width: 10.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(message.text,
                        style: TextStyle(fontSize: 13.sp, height: 1.4, color: AppColors.ink)),
                    SizedBox(height: 2.h),
                    Text('Tap to view in Reminders',
                        style: TextStyle(
                            fontSize: 11.5.sp,
                            fontWeight: FontWeight.w700,
                            color: AppColors.ai)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: AppColors.ai),
            ],
          ),
        ),
      ),
    );
  }
}

/// When MedAI needs a missing reminder detail (usually time or frequency),
/// it asks a short question and offers a few tappable suggestions instead
/// of guessing — tapping one sends it as a normal message, same as if the
/// user had typed it.
class _QuickReplyCard extends StatelessWidget {
  const _QuickReplyCard({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final options = message.quickReplies ?? const [];
    return Padding(
      padding: EdgeInsets.only(bottom: 12.h),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * .85),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: EdgeInsets.symmetric(horizontal: 15.w, vertical: 11.h),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(18.r),
                    topRight: Radius.circular(18.r),
                    bottomRight: Radius.circular(18.r),
                    bottomLeft: Radius.circular(6.r),
                  ),
                  border: Border.all(color: AppColors.line),
                ),
                child: Text(message.text,
                    style: TextStyle(fontSize: 14.sp, height: 1.45, color: AppColors.ink)),
              ),
              if (options.isNotEmpty) ...[
                SizedBox(height: 8.h),
                Wrap(
                  spacing: 8.w,
                  runSpacing: 8.h,
                  children: [
                    for (final option in options)
                      GestureDetector(
                        onTap: () => context.read<ChatProvider>().send(option),
                        child: Container(
                          padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 9.h),
                          decoration: BoxDecoration(
                            color: AppColors.aiSoft,
                            borderRadius: BorderRadius.circular(20.r),
                            border: Border.all(color: AppColors.ai.withValues(alpha: .35)),
                          ),
                          child: Text(option,
                              style: TextStyle(
                                  fontSize: 13.sp,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.ai)),
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _TypingBubble extends StatelessWidget {
  const _TypingBubble({this.label = 'MedAI is thinking…'});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.only(bottom: 10.h),
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18.r),
          border: Border.all(color: AppColors.line, width: 1.w),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 13.sp,
                fontStyle: FontStyle.italic,
                color: AppColors.muted)),
      ),
    );
  }
}