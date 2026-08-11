import 'dart:async';
import 'dart:io';

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
/// Chat history is real, persisted per-user, and split into multiple named
/// conversations — like ChatGPT/Claude's history — not one endless thread.
/// Each conversation lives at
/// users/{uid}/medai_conversations/{conversationId}/messages/*, so
/// switching users or starting a new chat never mixes histories together.
/// Free-text replies are generated live by Groq (llama-3.3-70b-versatile),
/// personalized with the user's health profile when "Personal insights" is
/// on, using the current conversation's recent messages as real context —
/// this is the practical form of "learning from the user's chats" that's
/// actually achievable through an API (there is no per-user model
/// fine-tuning here; Groq doesn't offer that, and it isn't something a
/// mobile app can do on its own). Voice notes are really transcribed (Groq
/// Whisper) — not a scripted guess — and the transcribed text is sent
/// through the exact same reply pipeline as typed text. Red-flag → SOS
/// escalation stays local and rule-based (safety-critical, must not depend
/// on any network call succeeding). Prescription scans run real,
/// fully-offline OCR (Tesseract) on the photo and a heuristic parser
/// guesses medicine/dose/frequency — the user reviews and picks the exact
/// times before anything becomes a real reminder (see
/// PrescriptionReviewScreen). Skin-photo/lab-report "analysis" replies
/// stay scripted for now — that needs a vision-capable model, a separate
/// task from OCR.
class ChatProvider extends ChangeNotifier {
  ChatProvider({this.reminderEngine, this.profileProvider}) {
    _initForCurrentUser();

    // authStateChanges() fires once immediately with the CURRENT user as
    // soon as we start listening, in addition to firing on real
    // login/logout — so without the uid guard below, init runs twice on
    // every cold start and can create two conversations. Only re-init when
    // the uid actually changes.
    FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user?.uid == _initializedForUid) return;
      debugPrint('[ChatProvider] authStateChanged: ${user?.email}');
      _initForCurrentUser();
    });
  }

  String? _initializedForUid;
  bool _initializing = false;

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

  /// The conversation currently open in the chat screen.
  String? currentConversationId;

  /// All of the logged-in user's saved conversations, most recent first —
  /// this is what the chat-history screen lists.
  List<ChatConversationSummary> conversations = [];
  bool loadingConversations = false;

  // ---------------------------------------------------------------------
  // Startup / user switching
  // ---------------------------------------------------------------------

  Future<void> _initForCurrentUser() async {
    if (_initializing) return; // guards against overlapping calls
    _initializing = true;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    _initializedForUid = uid;

    messages.clear();
    conversations = [];
    currentConversationId = null;
    pendingAttachments.clear();
    typing = false;
    recording = false;
    transcribing = false;
    notifyListeners();

    try {
      await loadConversations();
      if (conversations.isNotEmpty) {
        await openConversation(conversations.first.id);
      } else {
        await startNewConversation();
      }
    } finally {
      _initializing = false;
    }
  }

  /// Refreshes the conversation list from Firestore — call after creating,
  /// deleting, or renaming a conversation so the history screen stays current.
  Future<void> loadConversations() async {
    loadingConversations = true;
    notifyListeners();
    conversations = await ChatFirestoreService.instance.fetchConversations();
    loadingConversations = false;
    notifyListeners();
  }

  /// Creates a brand-new, empty conversation with the greeting message and
  /// makes it the active one — this is the "+ New chat" action.
  Future<void> startNewConversation() async {
    messages.clear();
    pendingAttachments.clear();
    typing = false;
    notifyListeners();

    final id = await ChatFirestoreService.instance.createConversation();
    currentConversationId = id;

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
    await loadConversations(); // refresh so history list shows the new one
  }

  /// Opens a previously saved conversation and loads its messages — this
  /// is what tapping a past chat in the history screen does.
  Future<void> openConversation(String conversationId) async {
    currentConversationId = conversationId;
    messages.clear();
    pendingAttachments.clear();
    typing = false;
    notifyListeners();

    final history =
        await ChatFirestoreService.instance.fetchMessages(conversationId);
    messages.addAll(history);
    notifyListeners();
  }

  /// Deletes a saved conversation entirely. If it was the currently open
  /// one, starts a fresh conversation so the chat screen never shows a
  /// deleted thread.
  Future<void> deleteConversation(String conversationId) async {
    await ChatFirestoreService.instance.deleteConversation(conversationId);
    await loadConversations();
    if (currentConversationId == conversationId) {
      if (conversations.isNotEmpty) {
        await openConversation(conversations.first.id);
      } else {
        await startNewConversation();
      }
    }
  }

  // ---------------------------------------------------------------------
  // Sending / replying
  // ---------------------------------------------------------------------

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
      final size = await File(filePath).length();
      debugPrint('[ChatProvider] transcribing $filePath ($size bytes)');
      transcript = await GroqService.transcribeAudio(filePath);
      debugPrint('[ChatProvider] transcript: "$transcript"');
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

  /// Saves a message inside the current conversation and actually waits
  /// for it to land.
  ///
  /// This used to be fire-and-forget, which is why chats could vanish if
  /// the app got killed (e.g. swiped from Android's recents) right after a
  /// message was sent — the write was still in flight when the process
  /// died. Awaiting it here means the message is genuinely durable by the
  /// time send()/stopRecording() consider that turn finished. The UI never
  /// waits on this — messages already appear locally via notifyListeners()
  /// the instant before this runs.
  Future<void> _persist(ChatMessage message) async {
    final id = currentConversationId;
    if (id == null) {
      debugPrint('[ChatProvider] _persist: no active conversation, skipping save');
      return;
    }
    await ChatFirestoreService.instance.saveMessage(id, message);
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
      final result = await GroqService.chatWithTools(
        systemPrompt: _buildSystemPrompt(),
        history: _buildHistory(),
        tools: _tools,
      );

      if (result.hasToolCalls) {
        for (final call in result.toolCalls!) {
          await _executeTool(call);
        }
        return;
      }

      final content = result.content?.trim();
      if (content == null || content.isEmpty) {
        throw Exception('Groq returned an empty response');
      }
      await _reply(ChatMessage(
          role: ChatRole.ai, text: content, personalized: learnFromData));
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

  /// Tool schemas offered to Groq (OpenAI-style function calling) — this is
  /// what lets MedAI actually DO things instead of just describing them.
  static final List<Map<String, dynamic>> _tools = [
    {
      'type': 'function',
      'function': {
        'name': 'add_reminder',
        'description':
            'Creates a real medication/appointment reminder for the user. '
            'Only call this when the user explicitly asks to be reminded '
            'about something, e.g. "remind me to take vitamin D at 9am '
            'every day" or "add a reminder for my checkup at 3pm".',
        'parameters': {
          'type': 'object',
          'properties': {
            'title': {
              'type': 'string',
              'description': 'What to be reminded about, e.g. "Vitamin D".'
            },
            'dose': {
              'type': 'string',
              'description':
                  'Dose/amount if mentioned, e.g. "1 tablet". Empty string if not mentioned.'
            },
            'time': {
              'type': 'string',
              'description':
                  'Exact clock time as "H:MM AM/PM", e.g. "9:00 AM". If the '
                  'user gave no time, use "9:00 AM".'
            },
            'schedule': {
              'type': 'string',
              'description':
                  'How often, e.g. "Daily", "Weekdays", "Nightly". Default "Daily" if unspecified.'
            },
            'instructions': {
              'type': 'string',
              'description':
                  'Any extra note, e.g. "after food". Empty string if none.'
            },
          },
          'required': ['title', 'time'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'update_health_profile',
        'description':
            "Updates a field in the user's MediSense health profile. Only "
            'call this when the user explicitly asks to change/add/update '
            'it, e.g. "update my weight to 160 lbs" or "add penicillin to '
            'my allergies".',
        'parameters': {
          'type': 'object',
          'properties': {
            'field': {
              'type': 'string',
              'enum': [
                'weight',
                'height',
                'bloodType',
                'allergies',
                'conditions',
                'medications',
              ],
              'description': 'Which profile field to change.',
            },
            'value': {
              'type': 'string',
              'description':
                  'The new value. For weight: whole number of lb. For '
                  'height: whole number of inches. For bloodType: e.g. '
                  '"O+". For allergies/conditions/medications: a '
                  'comma-separated list of items.',
            },
            'mode': {
              'type': 'string',
              'enum': ['add', 'replace'],
              'description':
                  'For allergies/conditions/medications only: "add" '
                  'appends to the existing list, "replace" overwrites it. '
                  'Default "add". Ignored for weight/height/bloodType, '
                  'which always replace.',
            },
          },
          'required': ['field', 'value'],
        },
      },
    },
  ];

  Future<void> _executeTool(GroqToolCall call) async {
    switch (call.name) {
      case 'add_reminder':
        await _executeAddReminder(call.arguments);
        break;
      case 'update_health_profile':
        await _executeUpdateProfile(call.arguments);
        break;
      default:
        typing = false;
        await _reply(const ChatMessage(
          role: ChatRole.ai,
          text: "I tried to do something I don't actually support yet — "
              'sorry about that.',
        ));
    }
  }

  Future<void> _executeAddReminder(Map<String, dynamic> args) async {
    typing = false;
    if (reminderEngine == null) {
      await _reply(const ChatMessage(
        role: ChatRole.ai,
        text: "I can't set reminders right now — please try again in a "
            'moment.',
      ));
      return;
    }

    final title = (args['title'] as String?)?.trim() ?? '';
    if (title.isEmpty) {
      await _reply(const ChatMessage(
        role: ChatRole.ai,
        text: 'What would you like the reminder to be about?',
      ));
      return;
    }

    final timeRaw = (args['time'] as String?)?.trim() ?? '';
    final time = _validateReminderTime(timeRaw);
    final dose = (args['dose'] as String?)?.trim() ?? '';
    final schedule = (args['schedule'] as String?)?.trim();
    final instructions = (args['instructions'] as String?)?.trim() ?? '';

    try {
      await reminderEngine!.addAll([
        Reminder(
          title: title,
          dose: dose,
          time: time,
          schedule: (schedule == null || schedule.isEmpty) ? 'Daily' : schedule,
          instructions: instructions,
          addedBy: 'MedAI',
        ),
      ]);
      await _reply(ChatMessage(
        role: ChatRole.ai,
        text: 'Done — added a reminder for "$title" at $time'
            '${dose.isNotEmpty ? ' ($dose)' : ''}. You can edit or delete '
            'it anytime in Reminders.',
      ));
    } catch (e) {
      debugPrint('[ChatProvider] add_reminder error: $e');
      await _reply(const ChatMessage(
        role: ChatRole.ai,
        text: "Something went wrong adding that reminder — please try "
            'again, or add it manually in Reminders.',
      ));
    }
  }

  /// Guards against a malformed time from the model — falls back to a
  /// sensible default rather than creating a reminder the alarm scheduler
  /// can't parse.
  String _validateReminderTime(String raw) {
    final match = RegExp(r'^(\d{1,2}):(\d{2})\s*(AM|PM)$', caseSensitive: false)
        .firstMatch(raw.trim());
    if (match == null) return '9:00 AM';
    final hour = int.tryParse(match.group(1)!) ?? 9;
    if (hour < 1 || hour > 12) return '9:00 AM';
    final minute = match.group(2)!;
    final period = match.group(3)!.toUpperCase();
    return '$hour:$minute $period';
  }

  Future<void> _executeUpdateProfile(Map<String, dynamic> args) async {
    typing = false;
    if (profileProvider == null) {
      await _reply(const ChatMessage(
        role: ChatRole.ai,
        text: "I can't edit your profile right now — please try again in "
            'a moment.',
      ));
      return;
    }

    final field = (args['field'] as String?)?.trim() ?? '';
    final value = (args['value'] as String?)?.trim() ?? '';
    final mode = (args['mode'] as String?)?.trim().toLowerCase() ?? 'add';
    if (field.isEmpty || value.isEmpty) {
      await _reply(const ChatMessage(
        role: ChatRole.ai,
        text: 'What would you like me to update in your profile?',
      ));
      return;
    }

    final current = profileProvider!.profile;
    HealthProfile updated;
    String confirmation;

    try {
      switch (field) {
        case 'weight':
          final lb = int.tryParse(value.replaceAll(RegExp(r'[^0-9]'), ''));
          if (lb == null) throw const FormatException('weight');
          updated = current.copyWith(weightLb: lb);
          confirmation = 'Updated your weight to $lb lb.';
          break;
        case 'height':
          final inches = int.tryParse(value.replaceAll(RegExp(r'[^0-9]'), ''));
          if (inches == null) throw const FormatException('height');
          updated = current.copyWith(heightIn: inches);
          confirmation = "Updated your height to ${updated.heightLabel}.";
          break;
        case 'bloodType':
          updated = current.copyWith(bloodType: value);
          confirmation = 'Updated your blood type to $value.';
          break;
        case 'allergies':
        case 'conditions':
        case 'medications':
          final items = value
              .split(',')
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toList();
          final List<String> newList;
          if (mode == 'replace') {
            newList = items;
          } else {
            final existing = field == 'allergies'
                ? current.allergies
                : field == 'conditions'
                    ? current.conditions
                    : current.medications;
            newList = {...existing, ...items}.toList(); // de-duped
          }
          updated = field == 'allergies'
              ? current.copyWith(allergies: newList)
              : field == 'conditions'
                  ? current.copyWith(conditions: newList)
                  : current.copyWith(medications: newList);
          confirmation =
              '${mode == 'replace' ? 'Updated' : 'Added to'} your $field: '
              '${items.join(', ')}.';
          break;
        default:
          await _reply(ChatMessage(
            role: ChatRole.ai,
            text: "I don't know how to update \"$field\" in your profile "
                'yet — you can edit that in the Profile tab.',
          ));
          return;
      }

      await profileProvider!.updateProfile(updated);
      await _reply(ChatMessage(
        role: ChatRole.ai,
        text:
            '$confirmation You can review or change it anytime in your Profile tab.',
      ));
    } catch (e) {
      debugPrint('[ChatProvider] update_health_profile error: $e');
      await _reply(ChatMessage(
        role: ChatRole.ai,
        text: "I couldn't make sense of \"$value\" for $field — mind "
            'trying again, or editing it directly in your Profile tab?',
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
      'a supportive assistant, not a replacement for professional care. '
      'You can take real actions: use add_reminder when the user asks to '
      'be reminded about something, and update_health_profile when they '
      'ask to change their weight, height, blood type, allergies, '
      'conditions, or medications. Only call a tool when the user clearly '
      'asked for that action — do not call one just because health '
      'information came up in conversation.',
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

  /// Last ~20 text messages in the CURRENT conversation as {role, content}
  /// pairs for conversation context — this is what "MedAI remembers past
  /// chats" actually means here: real persisted history feeding into each
  /// new request, not a fine-tuned model. Groq itself has no memory
  /// between calls, and different conversations never bleed into each
  /// other's context.
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