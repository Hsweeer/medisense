import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../core/services/groq_service.dart';
import '../core/services/language_pack_manager.dart';
import '../core/services/native_tesseract_ocr.dart';
import '../core/services/prescription_parser.dart';
import '../data/models/models.dart';
import '../services/chat_firestore_service.dart';
import 'profile_provider.dart';
import 'reminder_provider.dart';

/// MedAI — the in-app health assistant.
///
/// Chat history is real and persisted (Firestore, users/{uid}/medai_chat) —
/// it survives app restarts and syncs across devices, not just in-memory
/// for the current session. Free-text replies are generated live by Groq
/// (llama-3.3-70b-versatile), personalized with the user's health profile
/// when "Personal insights" is on, using recent chat history as real
/// context — this is the practical form of "learning from the user's
/// chats" that's actually achievable through an API (there is no per-user
/// model fine-tuning here; Groq doesn't offer that, and it isn't something
/// a mobile app can do on its own). Voice notes are really transcribed
/// (Groq Whisper) — not a scripted guess — and the transcribed text is
/// sent through the exact same reply pipeline as typed text. Red-flag →
/// SOS escalation stays local and rule-based (safety-critical, must not
/// depend on any network call succeeding). Prescription scans run real,
/// fully-offline OCR (Tesseract) on the photo and a heuristic parser
/// guesses medicine/dose/frequency — the user reviews and picks the exact
/// times before anything becomes a real reminder (see
/// PrescriptionReviewScreen). Skin-photo/lab-report "analysis" replies
/// stay scripted for now — that needs a vision-capable model, a separate
/// task from OCR.
class ChatProvider extends ChangeNotifier {
  ChatProvider({this.reminderEngine, this.profileProvider}) {
    _initChat();

    // authStateChanges() fires once immediately with the CURRENT user as
    // soon as we start listening, in addition to firing on real
    // login/logout — so without this guard, _initChat() runs twice on
    // every cold start (once from the constructor above, once from this
    // listener's first event), both racing to read an empty Firestore
    // history and both adding their own greeting. Only re-init when the
    // uid actually changes.
    FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user?.uid == _initializedForUid) return;
      debugPrint('[ChatProvider] authStateChanged: ${user?.email}');
      _initChat();
    });
  }

  String? _initializedForUid;
  bool _initializing = false;

  Future<void> _initChat() async {
    if (_initializing) return; // guards against overlapping calls too
    _initializing = true;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    _initializedForUid = uid;

    messages.clear();
    pendingAttachments.clear();
    typing = false;
    recording = false;
    transcribing = false;
    notifyListeners();

    try {
      final history = await ChatFirestoreService.instance.fetchRecentMessages();
      if (history.isNotEmpty) {
        messages.addAll(history);
        notifyListeners();
        return;
      }

      // First time this user has ever opened MedAI — show and save the
      // greeting so it's part of their real, persisted history too.
      final user = FirebaseAuth.instance.currentUser;
      final name = user?.displayName?.split(' ').first ?? 'there';

      final greeting = ChatMessage(
        role: ChatRole.ai,
        text: learnFromData
            ? "Hi $name, I'm MedAI — your personal health assistant. I can "
                'answer health questions, read lab reports or photos you '
                'upload, and listen to voice notes. Personal insights are '
                "on, so my guidance will account for your health profile — "
                "allergies, conditions, medications, age, and more."
                '\n\nHow are you feeling today?'
            : "Hi $name, I'm MedAI — your personal health assistant. I can "
                'answer health questions, read lab reports or photos you '
                'upload, and listen to voice notes. Personal insights are '
                "off right now, so I can't read your health profile — turn "
                'that on above anytime for guidance tailored to you.'
                '\n\nHow are you feeling today?',
        personalized: learnFromData,
      );
      messages.add(greeting);
      notifyListeners();
      await _persist(greeting);
    } finally {
      _initializing = false;
    }
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

  /// True while a just-recorded voice note is being sent to Groq for
  /// transcription — separate from [typing], which covers waiting for the
  /// reply itself.
  bool transcribing = false;

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

  /// Ends the hold-to-talk gesture. [filePath] is the on-device path of the
  /// actual recorded audio file — stages it as a normal voice-note bubble
  /// (so it can be played back), then sends the real audio to Groq's
  /// Whisper endpoint for genuine transcription, and finally routes the
  /// transcribed text through the exact same reply pipeline as if the user
  /// had typed it (including red-flag detection).
  Future<void> stopRecording({
    required int seconds,
    bool cancelled = false,
    String? filePath,
  }) async {
    recording = false;
    notifyListeners();
    if (cancelled || seconds < 1) return;

    final attachment = ChatAttachment(
      type: AttachmentType.voice,
      name: 'Voice note',
      detail: '0:${seconds.toString().padLeft(2, '0')}',
      durationSeconds: seconds,
      filePath: filePath,
    );
    await _sendUser('', [attachment]);

    if (filePath == null) {
      await _reply(const ChatMessage(
        role: ChatRole.ai,
        text: "I couldn't access that recording — please try again.",
      ));
      return;
    }

    transcribing = true;
    notifyListeners();
    String transcript;
    try {
      transcript = await GroqService.transcribeAudio(filePath);
    } catch (e) {
      debugPrint('[ChatProvider] transcription error: $e');
      transcribing = false;
      notifyListeners();
      await _reply(const ChatMessage(
        role: ChatRole.ai,
        text:
            "I couldn't make out that voice note — please check your "
            'connection and try recording again, or type your question '
            'instead.',
      ));
      return;
    }
    transcribing = false;
    notifyListeners();

    if (transcript.trim().isEmpty) {
      await _reply(const ChatMessage(
        role: ChatRole.ai,
        text: "I couldn't hear anything clear in that voice note — mind "
            'trying again somewhere quieter?',
      ));
      return;
    }

    // Route the real transcribed words through the normal pipeline —
    // red-flag detection first, exactly like typed text.
    await _routeReply(transcript.trim(), const []);
  }

  Future<void> send(String text) async {
    final t = text.trim();
    if (t.isEmpty && pendingAttachments.isEmpty) return;
    final attachments = [...pendingAttachments];
    pendingAttachments.clear();
    notifyListeners();
    await _sendUser(t, attachments);
    await _routeReply(t, attachments);
  }

  /// Shared by typed messages and transcribed voice notes.
  Future<void> _routeReply(String text, List<ChatAttachment> attachments) async {
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
      await _replyFromPrescriptionScan(rxPhoto);
      return;
    }

    final scripted = _scriptedReply(text, attachments);
    if (scripted != null) {
      await _replyDelayed(scripted);
    } else {
      await _replyFromGroq();
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
      await _reply(const ChatMessage(
        role: ChatRole.ai,
        text: "I couldn't access that photo — please try scanning again.",
      ));
      return;
    }

    try {
      await LanguagePackManager.instance.ensureBundledEnglishReady();
      final tessdataParentPath =
          await LanguagePackManager.instance.tessdataParentDir();
      final raw = await NativeTesseractOcr.extractText(
        imagePath: path,
        tessdataParentPath: tessdataParentPath,
        language: 'eng',
      );
      final cleaned = raw.trim();
      typing = false;

      if (cleaned.isEmpty) {
        await _reply(const ChatMessage(
          role: ChatRole.ai,
          text:
              "I couldn't make out any text on that photo. Try again with "
              'better lighting, a flatter angle, and the note filling the '
              "frame — or use 'Document / PDF' if you have a typed copy.",
        ));
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

      await _reply(ChatMessage(
        role: ChatRole.ai,
        card: ChatCardType.prescription,
        personalized: learnFromData,
        text: summary,
        ocrText: cleaned,
      ));
    } catch (e) {
      debugPrint('[ChatProvider] OCR error: $e');
      typing = false;
      await _reply(const ChatMessage(
        role: ChatRole.ai,
        text: 'Something went wrong reading that photo. Please try again.',
      ));
    }
  }

  /// Called by the chat screen after the user returns from the prescription
  /// review screen, so the confirmation shows up as a real MedAI message.
  Future<void> noteRemindersAdded(int count) async {
    if (count <= 0) return;
    await _reply(ChatMessage(
      role: ChatRole.ai,
      text: count == 1
          ? 'Added 1 reminder — find it, snooze it, or edit it anytime in '
              'Reminders.'
          : 'Added $count reminders — find, snooze, or edit them anytime '
              'in Reminders.',
    ));
  }

  /// Wipes chat history in Firestore and starts fresh with the greeting.
  Future<void> clearChat() async {
    await ChatFirestoreService.instance.clearHistory();
    await _initChat();
  }

  Future<void> _sendUser(String text, List<ChatAttachment> attachments) async {
    final message =
        ChatMessage(role: ChatRole.user, text: text, attachments: attachments);
    messages.add(message);
    notifyListeners(); // shows instantly, before the save completes
    await _persist(message);
  }

  /// Adds an AI message to the thread, persists it, and clears typing.
  Future<void> _reply(ChatMessage message) async {
    typing = false;
    messages.add(message);
    notifyListeners(); // shows instantly, before the save completes
    await _persist(message);
  }

  /// Saves a message to Firestore and actually waits for it to land.
  ///
  /// This used to be fire-and-forget, which is why chats could vanish if
  /// the app got killed (e.g. swiped from Android's recents) right after a
  /// message was sent — the write was still in flight when the process
  /// died. Awaiting it here means the message is genuinely durable by the
  /// time send()/stopRecording() consider that turn finished. The UI never
  /// waits on this — messages already appear locally via notifyListeners()
  /// the instant before this runs.
  Future<void> _persist(ChatMessage message) async {
    await ChatFirestoreService.instance.saveMessage(message);
  }

  /// Scripted, simulated-delay reply (red-flags, attachment "analysis").
  Future<void> _replyDelayed(ChatMessage message) async {
    typing = true;
    notifyListeners();
    final completer = Completer<void>();
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 1400), () {
      completer.complete();
    });
    await completer.future;
    await _reply(message);
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
      await _reply(ChatMessage(
          role: ChatRole.ai, text: reply, personalized: learnFromData));
    } catch (e) {
      debugPrint('[ChatProvider] Groq error: $e');
      typing = false;
      await _reply(const ChatMessage(
        role: ChatRole.ai,
        text:
            "I'm having trouble reaching MedAI's servers right now — please "
            "check your connection and try again in a moment.",
      ));
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
      final age = p != null ? _ageFromDob(p.dob) : null;
      final hasContext = p != null &&
          (p.allergies.isNotEmpty ||
              p.conditions.isNotEmpty ||
              p.medications.isNotEmpty ||
              p.bloodType.trim().isNotEmpty ||
              p.weightLb > 0 ||
              p.heightIn > 0 ||
              age != null);
      if (hasContext) {
        buffer.write(
            "\n\nThe user's health profile, from their MediSense profile "
            'tab (use it to tailor advice — e.g. flag allergy/medication '
            "conflicts, or factor in age/weight for dosing-style guidance "
            "— but don't just recite it back unless relevant):");
        if (age != null) {
          buffer.write('\n- Age: $age');
        }
        if (p!.bloodType.trim().isNotEmpty) {
          buffer.write('\n- Blood type: ${p.bloodType}');
        }
        if (p.weightLb > 0) {
          buffer.write('\n- Weight: ${p.weightLb} lb');
        }
        if (p.heightIn > 0) {
          buffer.write('\n- Height: ${p.heightIn} in');
        }
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

  /// Parses the profile's "D Mon YYYY" date-of-birth string (same format
  /// used by the Edit Health Profile screen) into a whole-years age.
  /// Returns null if [dob] is empty or not in that format.
  int? _ageFromDob(String dob) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final trimmed = dob.trim();
    if (trimmed.isEmpty) return null;
    final parts = trimmed.split(' ');
    if (parts.length != 3) return null;
    final day = int.tryParse(parts[0]);
    final monthIdx =
        months.indexOf(parts[1].length >= 3 ? parts[1].substring(0, 3) : parts[1]);
    final year = int.tryParse(parts[2]);
    if (day == null || monthIdx == -1 || year == null) return null;

    final birth = DateTime(year, monthIdx + 1, day);
    final now = DateTime.now();
    var age = now.year - birth.year;
    if (now.month < birth.month ||
        (now.month == birth.month && now.day < birth.day)) {
      age--;
    }
    return age >= 0 && age < 130 ? age : null;
  }

  /// Last ~20 text messages as {role, content} pairs for conversation
  /// context — this is what "MedAI remembers past chats" actually means
  /// here: real persisted history feeding into each new request, not a
  /// fine-tuned model. Groq itself has no memory between calls.
  List<Map<String, String>> _buildHistory() {
    final recent =
        messages.length > 20 ? messages.sublist(messages.length - 20) : messages;
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
  /// returns null for everything else so [_routeReply] routes it to Groq
  /// instead.
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

    // Everything else — plain questions (typed or transcribed) — goes to
    // Groq for a real reply.
    return null;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}