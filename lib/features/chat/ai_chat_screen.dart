import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/shared_widgets.dart';
import '../../data/mock/mock_data.dart';
import '../../data/models/models.dart';
import '../../providers/chat_provider.dart';
import '../../providers/sos_provider.dart';
import '../reminders/reminders_screen.dart';
import '../sos/sos_screen.dart';

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
  DateTime? _recordStart;

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _send() {
    context.read<ChatProvider>().send(_ctrl.text);
    _ctrl.clear();
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
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Share with MedAI',
                  style: GoogleFonts.sora(
                      fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              _AttachRow(
                icon: Icons.photo_camera_rounded,
                color: AppColors.primary,
                soft: AppColors.soft,
                title: 'Camera',
                sub: 'Take a photo of anything',
                onTap: () => _stage(
                    chat,
                    const ChatAttachment(
                        type: AttachmentType.image,
                        name: 'Photo — camera',
                        detail: 'Camera · JPG')),
              ),
              _AttachRow(
                icon: Icons.photo_library_rounded,
                color: AppColors.primary,
                soft: AppColors.soft,
                title: 'Photo library',
                sub: 'Pick from your gallery',
                onTap: () => _stage(
                    chat,
                    const ChatAttachment(
                        type: AttachmentType.image,
                        name: 'IMG_2481.jpg',
                        detail: 'Photo · 1.8 MB')),
              ),
              _AttachRow(
                icon: Icons.description_rounded,
                color: AppColors.warning,
                soft: AppColors.warningSoft,
                title: 'Document / PDF',
                sub: 'Lab reports, medical records',
                onTap: () => _stage(
                    chat,
                    const ChatAttachment(
                        type: AttachmentType.file,
                        name: 'Lab-results-June.pdf',
                        detail: 'PDF · 2.4 MB')),
              ),
              _AttachRow(
                icon: Icons.receipt_long_rounded,
                color: AppColors.ai,
                soft: AppColors.aiSoft,
                title: 'Scan prescription',
                sub: 'MedAI reads the doctor\'s note & sets alarms itself',
                onTap: () => _stage(
                    chat,
                    const ChatAttachment(
                        type: AttachmentType.image,
                        name: 'Prescription — clinic note',
                        detail: 'Scan · JPG',
                        intent: AttachmentIntent.prescription)),
              ),
              _AttachRow(
                icon: Icons.face_retouching_natural_rounded,
                color: AppColors.ai,
                soft: AppColors.aiSoft,
                title: 'Skin check',
                sub: 'Detect a skin condition from a photo',
                onTap: () => _stage(
                    chat,
                    const ChatAttachment(
                        type: AttachmentType.image,
                        name: 'Skin check photo',
                        detail: 'Camera · JPG',
                        intent: AttachmentIntent.skin)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _stage(ChatProvider chat, ChatAttachment a) {
    Navigator.of(context).pop();
    chat.stageAttachment(a);
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
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: AppColors.aiGradient),
                borderRadius: BorderRadius.circular(11),
              ),
              child: const Icon(Icons.psychology_alt_rounded,
                  color: Colors.white, size: 20),
            ),
            const SizedBox(width: 10),
            const Text('MedAI'),
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
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: const Text(
              '⚠ MedAI offers general guidance — not a diagnosis. '
              'In an emergency call 911.',
              style: TextStyle(
                  fontSize: 12,
                  color: Color(0xFF8A5B0B),
                  fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
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
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              children: [
                for (final s in MockData.aiSuggestions)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
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
              height: 54,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              alignment: Alignment.centerLeft,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final a in chat.pendingAttachments)
                    Container(
                      margin: const EdgeInsets.only(right: 8, top: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: AppColors.soft,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(
                              a.type == AttachmentType.image
                                  ? Icons.image_rounded
                                  : Icons.description_rounded,
                              size: 16,
                              color: AppColors.onSoft),
                          const SizedBox(width: 6),
                          Text(a.name,
                              style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.onSoft)),
                          const SizedBox(width: 6),
                          GestureDetector(
                            onTap: () => chat.removeStaged(a),
                            child: const Icon(Icons.close_rounded,
                                size: 15, color: AppColors.onSoft),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: _openAttachmentSheet,
                    child: Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.line),
                      ),
                      child: const Icon(Icons.add_rounded,
                          color: AppColors.inkSoft),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _ctrl,
                      decoration: const InputDecoration(
                          hintText: 'Ask MedAI anything…'),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Hold to record a voice note.
                  GestureDetector(
                    onLongPressStart: (_) {
                      _recordStart = DateTime.now();
                      chat.startRecording();
                    },
                    onLongPressEnd: (_) {
                      final secs = DateTime.now()
                          .difference(_recordStart ?? DateTime.now())
                          .inSeconds;
                      chat.stopRecording(seconds: max(secs, 2));
                    },
                    onTap: () => showToast(
                        context, 'Hold the mic to record a voice note'),
                    child: Container(
                      width: 46,
                      height: 46,
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
                          color: chat.recording
                              ? Colors.white
                              : AppColors.inkSoft),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _send,
                    child: Container(
                      width: 46,
                      height: 46,
                      decoration: const BoxDecoration(
                        gradient:
                            LinearGradient(colors: AppColors.aiGradient),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.send_rounded,
                          color: Colors.white, size: 21),
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
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                  color: soft, borderRadius: BorderRadius.circular(11)),
              child: Icon(icon, color: color, size: 19),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 13.5, fontWeight: FontWeight.w700)),
                  Text(sub,
                      style: const TextStyle(
                          fontSize: 11.5, color: AppColors.muted)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                size: 18, color: AppColors.muted),
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
        padding: const EdgeInsets.only(bottom: 12),
        child: MCard(
          color: AppColors.dangerSoft,
          border: Border.all(color: AppColors.danger, width: 1.4),
          onTap: () {
            context.read<SosProvider>().trigger();
            Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const SosScreen()));
          },
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: const BoxDecoration(
                    color: AppColors.danger, shape: BoxShape.circle),
                child: const Icon(Icons.sos_rounded,
                    color: Colors.white, size: 26),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('This may be an emergency',
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            color: AppColors.danger)),
                    const SizedBox(height: 2),
                    Text(message.text,
                        style: const TextStyle(
                            fontSize: 12.5, color: AppColors.inkSoft)),
                    const SizedBox(height: 4),
                    const Text('TAP TO OPEN EMERGENCY SOS →',
                        style: TextStyle(
                            fontSize: 11.5,
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
        margin: const EdgeInsets.only(bottom: 10),
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
                    const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
                decoration: BoxDecoration(
                  color: isUser ? AppColors.primary : Colors.white,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(18),
                    topRight: const Radius.circular(18),
                    bottomLeft: Radius.circular(isUser ? 18 : 6),
                    bottomRight: Radius.circular(isUser ? 6 : 18),
                  ),
                  border:
                      isUser ? null : Border.all(color: AppColors.line),
                ),
                child: Text(message.text,
                    style: TextStyle(
                        fontSize: 14,
                        height: 1.45,
                        color: isUser ? Colors.white : AppColors.ink)),
              ),
            if (!isUser && message.personalized)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: MChip('Tailored to your health profile',
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
        width: 190,
        height: 120,
        margin: const EdgeInsets.only(bottom: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFD8E8E4), Color(0xFFBFD9D2)],
          ),
        ),
        child: Stack(
          children: [
            const Center(
                child: Icon(Icons.image_rounded,
                    size: 38, color: Colors.white)),
            Positioned(
              left: 8,
              bottom: 8,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: .45),
                    borderRadius: BorderRadius.circular(8)),
                child: Text(attachment.name,
                    style: const TextStyle(
                        fontSize: 10.5,
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
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
                color: AppColors.warningSoft,
                borderRadius: BorderRadius.circular(11)),
            child: const Icon(Icons.description_rounded,
                color: AppColors.warning, size: 20),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(attachment.name,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700)),
              Text(attachment.detail,
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.muted)),
            ],
          ),
        ],
      ),
    );
  }
}

class _VoiceBubble extends StatelessWidget {
  const _VoiceBubble({required this.attachment});

  final ChatAttachment attachment;

  @override
  Widget build(BuildContext context) {
    final rng = Random(attachment.durationSeconds);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 24),
          const SizedBox(width: 6),
          Row(
            children: [
              for (var i = 0; i < 22; i++)
                Container(
                  width: 2.6,
                  height: 6 + rng.nextDouble() * 16,
                  margin: const EdgeInsets.symmetric(horizontal: 1.1),
                  decoration: BoxDecoration(
                    color: Colors.white
                        .withValues(alpha: i < 14 ? 1 : .45),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 8),
          Text(attachment.detail,
              style: const TextStyle(
                  fontSize: 12,
                  color: Colors.white,
                  fontWeight: FontWeight.w600)),
        ],
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
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
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
                          width: 3.4,
                          height: 8 +
                              rng.nextDouble() * 26 * (.4 + _wave.value * .6),
                          margin:
                              const EdgeInsets.symmetric(horizontal: 1.6),
                          decoration: BoxDecoration(
                            color: AppColors.danger,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 12),
              Text(
                  'Recording… 0:${_seconds.toString().padLeft(2, '0')}',
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              const Text('Release to send',
                  style:
                      TextStyle(fontSize: 12, color: AppColors.muted)),
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
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MCard(
            border: Border.all(color: AppColors.ai.withValues(alpha: .45)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                          color: AppColors.aiSoft,
                          borderRadius: BorderRadius.circular(10)),
                      child: const Icon(Icons.receipt_long_rounded,
                          color: AppColors.ai, size: 19),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text('Prescription scanned',
                          style: TextStyle(
                              fontSize: 14.5, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
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
                const Divider(height: 20),
                Text(message.text,
                    style: const TextStyle(
                        fontSize: 13, height: 1.45, color: AppColors.ink)),
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const RemindersScreen())),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    decoration: BoxDecoration(
                      color: AppColors.aiSoft,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.alarm_on_rounded,
                            size: 17, color: AppColors.ai),
                        SizedBox(width: 7),
                        Text('2 alarm reminders added — view & edit',
                            style: TextStyle(
                                fontSize: 12.5,
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
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: MChip('Tailored to your health profile',
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
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(added ? Icons.alarm_on_rounded : Icons.warning_amber_rounded,
              size: 17,
              color: added ? AppColors.success : AppColors.warning),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700)),
                Text(freq,
                    style: const TextStyle(
                        fontSize: 11.5, color: AppColors.muted)),
                if (flag != null)
                  Text(flag!,
                      style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.warning)),
              ],
            ),
          ),
          Text(added ? 'Reminder set' : 'Not added',
              style: TextStyle(
                  fontSize: 11,
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
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MCard(
            border: Border.all(color: AppColors.ai.withValues(alpha: .45)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                          color: AppColors.aiSoft,
                          borderRadius: BorderRadius.circular(10)),
                      child: const Icon(
                          Icons.face_retouching_natural_rounded,
                          color: AppColors.ai,
                          size: 19),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text('Skin analysis',
                          style: TextStyle(
                              fontSize: 14.5, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                for (final c in _conditions)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(c.$1,
                                  style: const TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600)),
                            ),
                            Text('${(c.$2 * 100).round()}%',
                                style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.ai)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: c.$2,
                            minHeight: 6,
                            backgroundColor: AppColors.paper,
                            color: AppColors.ai,
                          ),
                        ),
                      ],
                    ),
                  ),
                const Divider(height: 18),
                Text(message.text,
                    style: const TextStyle(
                        fontSize: 13, height: 1.45, color: AppColors.ink)),
                const SizedBox(height: 10),
                const Text('Visual estimate — not a diagnosis.',
                    style: TextStyle(
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                        color: AppColors.muted)),
              ],
            ),
          ),
          if (message.personalized)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: MChip('Tailored to your health profile',
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
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.line),
        ),
        child: const Text('MedAI is thinking…',
            style: TextStyle(
                fontSize: 13,
                fontStyle: FontStyle.italic,
                color: AppColors.muted)),
      ),
    );
  }
}
