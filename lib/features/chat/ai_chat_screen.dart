import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/shared_widgets.dart';
import '../../data/mock/mock_data.dart';
import '../../data/models/models.dart';
import '../../providers/chat_provider.dart';
import '../../providers/sos_provider.dart';
import '../reminders/reminders_screen.dart';
import '../sos/sos_screen.dart';
import '../vitals/vitals_scan_screen.dart';

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

  @override
  void dispose() {
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
      if (!await _recorder.hasPermission()) {
        if (mounted) {
          showToast(context, 'Microphone permission is needed to record a voice note',
              color: AppColors.danger);
        }
        return;
      }
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc),
          path: path);
      _recordingPath = path;
      _recordStart = DateTime.now();
      chat.startRecording();
    } catch (_) {
      if (mounted) {
        showToast(context, 'Could not start recording', color: AppColors.danger);
      }
    }
  }

  /// Stops the mic recording on release and sends the real audio file.
  Future<void> _stopVoiceRecording(ChatProvider chat) async {
    if (!chat.recording) return; // never actually started (e.g. permission denied)
    final secs = DateTime.now()
        .difference(_recordStart ?? DateTime.now())
        .inSeconds;
    String? path;
    try {
      path = await _recorder.stop();
    } catch (_) {
      // fall back to the path we started recording to
    }
    chat.stopRecording(
        seconds: max(secs, 1), filePath: path ?? _recordingPath);
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
                icon: Icons.photo_camera_rounded,
                color: AppColors.primary,
                soft: AppColors.soft,
                title: 'Camera',
                sub: 'Take a photo of anything',
                onTap: () => _pickAndStage(chat,
                    source: ImageSource.camera,
                    intent: AttachmentIntent.general,
                    detail: 'Camera · JPG'),
              ),
              _AttachRow(
                icon: Icons.photo_library_rounded,
                color: AppColors.primary,
                soft: AppColors.soft,
                title: 'Photo library',
                sub: 'Pick from your gallery',
                onTap: () => _pickAndStage(chat,
                    source: ImageSource.gallery,
                    intent: AttachmentIntent.general,
                    detail: 'Photo'),
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
                onTap: () => _pickAndStage(chat,
                    source: ImageSource.camera,
                    intent: AttachmentIntent.prescription,
                    detail: 'Scan · JPG'),
              ),
              _AttachRow(
                icon: Icons.face_retouching_natural_rounded,
                color: AppColors.ai,
                soft: AppColors.aiSoft,
                title: 'Skin check',
                sub: 'Detect a skin condition from a photo',
                onTap: () => _pickAndStage(chat,
                    source: ImageSource.camera,
                    intent: AttachmentIntent.skin,
                    detail: 'Camera · JPG'),
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

  /// Opens the real device camera or gallery and stages whatever the user
  /// actually picks — replaces the old placeholder that staged a fake
  /// hardcoded filename without ever opening anything.
  Future<void> _pickAndStage(
    ChatProvider chat, {
    required ImageSource source,
    required AttachmentIntent intent,
    required String detail,
  }) async {
    Navigator.of(context).pop(); // close the attach sheet first
    try {
      final picked = await ImagePicker().pickImage(
        source: source,
        imageQuality: 85, // keeps upload size reasonable once wired to a real AI call
      );
      if (picked == null || !mounted) return; // user cancelled
      final fileName = picked.path.split(Platform.pathSeparator).last;
      chat.stageAttachment(ChatAttachment(
        type: AttachmentType.image,
        name: fileName,
        detail: detail,
        intent: intent,
        filePath: picked.path,
      ));
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
      chat.send('My heart rate scan result: ${bpm.round()} BPM');
    }
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatProvider>();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut);
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
          // "Personal insights" — the learn-from-your-data switch.
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: MChip(
              chat.learnFromData ? 'Personal insights ON' : 'Generic mode',
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
                        ? 'MedAI now tailors answers from your health profile'
                        : 'Personalization off — generic answers only');
              },
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: const Color(0xFFFDF3E3),
            padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 8.h),
            child: Text(
              '⚠ MedAI offers general guidance — not a diagnosis. '
              'In an emergency call 911.',
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
                  itemCount: chat.messages.length + (chat.typing ? 1 : 0),
                  itemBuilder: (_, i) {
                    if (i == chat.messages.length) {
                      return const _TypingBubble();
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
            context.read<SosProvider>().trigger();
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

    // Skin check → condition-probability analysis card.
    if (message.card == ChatCardType.skin) {
      return _SkinReportCard(message: message);
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
                child: Text(message.text,
                    style: TextStyle(
                        fontSize: 14.sp,
                        height: 1.45,
                        color: isUser ? Colors.white : AppColors.ink)),
              ),
            if (!isUser && message.personalized)
              Padding(
                padding: EdgeInsets.only(top: 4.h),
                child: const MChip('Tailored to your health profile',
                    icon: Icons.auto_awesome_rounded,
                    background: AppColors.aiSoft,
                    foreground: AppColors.ai),
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
      // Mock photo preview.
      return Container(
        width: 190.w,
        height: 120.h,
        margin: EdgeInsets.only(bottom: 6.h),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16.r),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFD8E8E4), Color(0xFFBFD9D2)],
          ),
        ),
        child: Stack(
          children: [
            Center(
                child: Icon(Icons.image_rounded,
                    size: 38.sp, color: Colors.white)),
            Positioned(
              left: 8.w,
              bottom: 8.h,
              child: Container(
                padding:
                    EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
                decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: .45),
                    borderRadius: BorderRadius.circular(8.r)),
                child: Text(attachment.name,
                    style: TextStyle(
                        fontSize: 10.5.sp,
                        color: Colors.white,
                        fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      );
    }
    // Document chip.
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
                const _MedRow(
                    name: 'Ibuprofen 400 mg',
                    freq: '2× daily · after food · 5 days',
                    added: true),
                const _MedRow(
                    name: 'Cetirizine 10 mg',
                    freq: 'Nightly · 7 days',
                    added: true),
                if (message.personalized)
                  const _MedRow(
                      name: 'Amoxicillin 500 mg',
                      freq: '3× daily · 7 days',
                      added: false,
                      flag: 'Penicillin allergy — ask your doctor'),
                Divider(height: 20.h),
                Text(message.text,
                    style: TextStyle(
                        fontSize: 13.sp, height: 1.45, color: AppColors.ink)),
                SizedBox(height: 12.h),
                GestureDetector(
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const RemindersScreen())),
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
                        Icon(Icons.alarm_on_rounded,
                            size: 17.sp, color: AppColors.ai),
                        SizedBox(width: 7.w),
                        Text('2 alarm reminders added — view & edit',
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
class _SkinReportCard extends StatelessWidget {
  const _SkinReportCard({required this.message});

  final ChatMessage message;

  static const _conditions = [
    ('Contact dermatitis', .72),
    ('Eczema flare', .18),
    ('Fungal infection', .06),
  ];

  @override
  Widget build(BuildContext context) {
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
                for (final c in _conditions)
                  Padding(
                    padding: EdgeInsets.only(bottom: 8.h),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(c.$1,
                                  style: TextStyle(
                                      fontSize: 12.5.sp,
                                      fontWeight: FontWeight.w600)),
                            ),
                            Text('${(c.$2 * 100).round()}%',
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
                            value: c.$2,
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
                SizedBox(height: 10.h),
                Text('Visual estimate — not a diagnosis.',
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

class _TypingBubble extends StatelessWidget {
  const _TypingBubble();

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
        child: Text('MedAI is thinking…',
            style: TextStyle(
                fontSize: 13.sp,
                fontStyle: FontStyle.italic,
                color: AppColors.muted)),
      ),
    );
  }
}