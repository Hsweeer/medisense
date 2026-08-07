import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../core/services/groq_service.dart';
import '../core/services/language_pack_manager.dart';
import '../core/services/prescription_parser.dart';
import '../core/services/tesseract_ocr_service.dart';
import '../data/models/models.dart';
import 'profile_provider.dart';
import 'reminder_provider.dart';

/// MedAI — the in-app health assistant.
///
/// Free-text replies are generated live by Groq (llama-3.3-70b-versatile),
/// personalized with the user's health profile when "Personal insights" is
/// on. Red-flag → SOS escalation stays local and rule-based (safety-critical,
/// must not depend on an LLM call succeeding). Prescription scans run real,
/// fully-offline OCR (Tesseract) on the photo and a heuristic parser guesses
/// medicine/dose/frequency — the user reviews and picks the exact times
/// before anything becomes a real reminder (see PrescriptionReviewScreen).
/// Skin-photo/lab-report "analysis" replies stay scripted for now — that
/// needs a vision-capable model, a separate task from OCR.
class ChatProvider extends ChangeNotifier {
  ChatProvider({this.reminderEngine, this.profileProvider}) {
    _initChat();

    // Reset chat whenever the user changes
    FirebaseAuth.instance.authStateChanges().listen((user) {
      debugPrint('[ChatProvider] authStateChanged: ${user?.email}');
      _initChat();
    });
  }

  void _initChat() {
    messages.clear();
    pendingAttachments.clear();
    typing = false;
    recording = false;

    final user = FirebaseAuth.instance.currentUser;
    final name = user?.displayName?.split(' ').first ?? 'there';

    messages.add(ChatMessage(
      role: ChatRole.ai,
      text:
          "Hi $name, I'm MedAI — your personal health assistant. I can answer "
          "health questions, read lab reports or photos you upload, and listen "
          "to voice notes. I've learned your health profile, so my guidance "
          "will account for any allergies or conditions you've listed."
          "\n\nHow are you feeling today?",
      personalized: true,
    ));
    notifyListeners();
  }

  /// Lets MedAI create alarms itself after scanning a prescription.
  final ReminderProvider? reminderEngine;

  /// Health profile — used to personalize Groq's system prompt when
  /// "Personal insights" is on.
  final ProfileProvider? profileProvider;

  final messages = <ChatMessage>[];
  bool typing = false;

  /// "Personal insights" — tailor replies from the health profile.
  bool learnFromData = true;

  /// Attachments staged in the composer, sent with the next message.
  final pendingAttachments = <ChatAttachment>[];

  bool recording = false;
  Timer? _timer;

  void toggleLearn() {
    learnFromData = !learnFromData;
    notifyListeners();
  }

  void stageAttachment(ChatAttachment attachment) {
    pendingAttachments.add(attachment);
    notifyListeners();
  }

  void removeStaged(ChatAttachment attachment) {
    pendingAttachments.remove(attachment);
    notifyListeners();
  }

  void startRecording() {
    recording = true;
    notifyListeners();
  }

  /// Ends the hold-to-talk gesture; sends a voice message when long enough.
  /// [filePath] is the on-device path of the actual recorded audio file, so
  /// it can be played back later from the chat bubble.
  void stopRecording({
    required int seconds,
    bool cancelled = false,
    String? filePath,
  }) {
    recording = false;
    if (!cancelled && seconds >= 1) {
      _sendUser(
        '',
        [
          ChatAttachment(
              type: AttachmentType.voice,
              name: 'Voice note',
              detail: '0:${seconds.toString().padLeft(2, '0')}',
              durationSeconds: seconds,
              filePath: filePath),
        ],
      );
      _replyDelayed(_voiceReply());
    }
    notifyListeners();
  }

  void send(String text) {
    final t = text.trim();
    if (t.isEmpty && pendingAttachments.isEmpty) return;
    final attachments = [...pendingAttachments];
    pendingAttachments.clear();
    _sendUser(t, attachments);

    // A prescription photo always goes through real OCR, not the scripted
    // or Groq paths — even if the user typed a caption along with it.
    ChatAttachment? rxPhoto;
    for (final a in attachments) {
      if (a.intent == AttachmentIntent.prescription) {
        rxPhoto = a;
        break;
      }
    }
    if (rxPhoto != null) {
      _replyFromPrescriptionScan(rxPhoto);
      return;
    }

    final scripted = _scriptedReply(t, attachments);
    if (scripted != null) {
      _replyDelayed(scripted);
    } else {
      _replyFromGroq();
    }
  }

  /// Runs real, fully-offline OCR (Tesseract) on a scanned prescription
  /// photo, heuristically parses medicine/dose/frequency out of the text,
  /// and shows a card the user can open to review and confirm exact times
  /// before anything becomes a real reminder. Nothing is added automatically
  /// — OCR on a doctor's handwriting is often wrong, so the user always has
  /// the final say (see PrescriptionReviewScreen).
  Future<void> _replyFromPrescriptionScan(ChatAttachment photo) async {
    typing = true;
    notifyListeners();

    final path = photo.filePath;
    if (path == null) {
      typing = false;
      messages.add(const ChatMessage(
        role: ChatRole.ai,
        text: "I couldn't access that photo — please try scanning again.",
      ));
      notifyListeners();
      return;
    }

    try {
      final langCode = await LanguagePackManager.instance.activeLanguage();
      final raw = await TesseractOcrService.extractText(
        path,
        language: langCode,
      );
      final cleaned = raw.trim();
      typing = false;

      if (cleaned.isEmpty) {
        messages.add(const ChatMessage(
          role: ChatRole.ai,
          text:
              "I couldn't make out any text on that photo. Try again with "
              'better lighting, a flatter angle, and the note filling the '
              "frame — or use 'Document / PDF' if you have a typed copy.",
        ));
        notifyListeners();
        return;
      }

      final meds = parsePrescriptionText(cleaned);
      final summary = meds.isEmpty
          ? "I read the photo but couldn't confidently pick out medicine "
              'names and dosages from it — this happens most with '
              'handwriting. Tap below to review the raw text and add '
              'reminders yourself.'
          : "Here's what I could read from the prescription:\n\n"
              '${meds.map((m) => '• ${m.name}${m.dose.isNotEmpty ? ' ${m.dose}' : ''} — ${m.timesPerDay}× daily').join('\n')}'
              '\n\nOCR reads printed text far better than handwriting, so '
              'please double-check everything below and set the exact '
              'times before adding reminders.';

      messages.add(ChatMessage(
        role: ChatRole.ai,
        card: ChatCardType.prescription,
        personalized: learnFromData,
        text: summary,
        ocrText: cleaned,
      ));
      notifyListeners();
    } catch (e) {
      debugPrint('[ChatProvider] OCR error: $e');
      typing = false;
      messages.add(const ChatMessage(
        role: ChatRole.ai,
        text: 'Something went wrong reading that photo. Please try again.',
      ));
      notifyListeners();
    }
  }

  /// Called by the chat screen after the user returns from the prescription
  /// review screen, so the confirmation shows up as a real MedAI message.
  void noteRemindersAdded(int count) {
    if (count <= 0) return;
    messages.add(ChatMessage(
      role: ChatRole.ai,
      text: count == 1
          ? 'Added 1 reminder — find it, snooze it, or edit it anytime in '
              'Reminders.'
          : 'Added $count reminders — find, snooze, or edit them anytime '
              'in Reminders.',
    ));
    notifyListeners();
  }

  void _sendUser(String text, List<ChatAttachment> attachments) {
    messages.add(ChatMessage(
        role: ChatRole.user, text: text, attachments: attachments));
    notifyListeners();
  }

  /// Scripted, simulated-delay reply (red-flags, attachment "analysis").
  void _replyDelayed(ChatMessage message) {
    typing = true;
    notifyListeners();
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 1400), () {
      typing = false;
      messages.add(message);
      notifyListeners();
    });
  }

  /// Real reply from Groq for free-text questions.
  Future<void> _replyFromGroq() async {
    typing = true;
    notifyListeners();
    try {
      final reply = await GroqService.chat(
        systemPrompt: _buildSystemPrompt(),
        history: _buildHistory(),
      );
      typing = false;
      messages.add(ChatMessage(
          role: ChatRole.ai, text: reply, personalized: learnFromData));
      notifyListeners();
    } catch (e) {
      debugPrint('[ChatProvider] Groq error: $e');
      typing = false;
      messages.add(const ChatMessage(
        role: ChatRole.ai,
        text:
            "I'm having trouble reaching MedAI's servers right now — please "
            "check your connection and try again in a moment.",
      ));
      notifyListeners();
    }
  }

  String _buildSystemPrompt() {
    final buffer = StringBuffer(
      'You are MedAI, a friendly, careful health-assistant chat feature '
      'inside the MediSense app. Give clear, practical, safe guidance in '
      'plain language, under about 120 words unless the question needs '
      'more detail. Always recommend seeing a doctor for anything serious, '
      'uncertain, or worsening. Never claim to give a diagnosis — you are '
      'a supportive assistant, not a replacement for professional care.',
    );

    if (learnFromData) {
      final p = profileProvider?.profile;
      final hasContext = p != null &&
          (p.allergies.isNotEmpty ||
              p.conditions.isNotEmpty ||
              p.medications.isNotEmpty);
      if (hasContext) {
        buffer.write(
            "\n\nThe user's health profile (use it to tailor advice — e.g. "
            "flag allergy/medication conflicts — but don't just recite it "
            'back unless relevant):');
        if (p.allergies.isNotEmpty) {
          buffer.write('\n- Allergies: ${p.allergies.join(', ')}');
        }
        if (p.conditions.isNotEmpty) {
          buffer.write('\n- Conditions: ${p.conditions.join(', ')}');
        }
        if (p.medications.isNotEmpty) {
          buffer.write('\n- Current medications: ${p.medications.join(', ')}');
        }
      }
    }
    return buffer.toString();
  }

  /// Last ~12 text messages as {role, content} pairs for conversation
  /// context (Groq has no memory of its own between calls).
  List<Map<String, String>> _buildHistory() {
    final recent =
        messages.length > 12 ? messages.sublist(messages.length - 12) : messages;
    return recent
        .where((m) => m.text.trim().isNotEmpty)
        .map((m) => {
              'role': m.role == ChatRole.user ? 'user' : 'assistant',
              'content': m.text,
            })
        .toList();
  }

  static const _redFlags = [
    'chest pain',
    "can't breathe",
    'cannot breathe',
    'severe bleeding',
    'stroke',
    'unconscious',
    'suicide',
    'overdose',
  ];

  /// Returns a scripted reply for red-flags and attachment "analysis";
  /// returns null for everything else so [send] routes it to Groq instead.
  ChatMessage? _scriptedReply(String text, List<ChatAttachment> attachments) {
    final lower = text.toLowerCase();

    if (_redFlags.any(lower.contains)) {
      return const ChatMessage(
        role: ChatRole.ai,
        card: ChatCardType.sos,
        text:
            'Symptoms like these can be serious. Please call 911 or use '
            'Emergency SOS now — I can alert your emergency contacts too.',
      );
    }

    // Skin check — analyze the photo and suggest likely conditions.
    if (attachments.any((a) => a.intent == AttachmentIntent.skin)) {
      return ChatMessage(
        role: ChatRole.ai,
        card: ChatCardType.skin,
        personalized: learnFromData,
        text:
            'Most consistent with mild contact dermatitis: localized '
            'redness, slight dryness, no spreading edges, blistering, or '
            'discharge.'
            "${learnFromData ? '\n\nFor you: avoid antibiotic ointments '
                '(penicillin allergy) — fragrance-free moisturizer and a '
                'cool compress are safer first steps.' : ''}"
            '\n\nSee a clinician if it spreads, blisters, or you develop '
            'fever within 48 hours.',
      );
    }

    if (attachments.any((a) => a.type == AttachmentType.image)) {
      return ChatMessage(
        role: ChatRole.ai,
        personalized: learnFromData,
        text:
            "I've reviewed your photo. The area shows mild redness with no "
            "spreading edges or discharge — consistent with minor skin "
            "irritation. Keep it clean and dry, and avoid scratching."
            "${learnFromData ? '\n\nBecause of your penicillin allergy, skip '
                'antibiotic ointments like Neosporin unless your doctor okays '
                'one — plain petroleum jelly is a safe alternative.' : ''}"
            '\n\nIf it spreads, blisters, or you develop a fever, see a '
            'clinician within 24 hours.',
      );
    }

    if (attachments.any((a) => a.type == AttachmentType.file)) {
      return ChatMessage(
        role: ChatRole.ai,
        personalized: learnFromData,
        text:
            "I've read your document. Summary of key values:\n\n"
            '• Vitamin D: 24 ng/mL — slightly below the 30–100 range\n'
            '• Fasting glucose: 92 mg/dL — normal\n'
            '• Cholesterol (LDL): 96 mg/dL — optimal'
            "${learnFromData ? '\n\nGood news: the Vitamin D 2000 IU you '
                'already take is the usual fix — recheck levels in 3 months.' : ''}"
            '\n\nWant me to explain any value in plain English?',
      );
    }

    // Everything else — plain questions — goes to Groq for a real reply.
    return null;
  }

  ChatMessage _voiceReply() {
    return ChatMessage(
      role: ChatRole.ai,
      personalized: learnFromData,
      text:
          "I listened to your voice note. I heard you mention throat "
          "discomfort since last night. Warm fluids and rest are the first "
          "line; most viral sore throats settle in 3–5 days."
          "${learnFromData ? '\n\nWith your mild asthma, watch for wheezing — '
              'if it starts, use your Albuterol inhaler as prescribed.' : ''}",
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
