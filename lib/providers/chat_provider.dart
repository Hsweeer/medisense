import 'dart:async';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../core/services/groq_service.dart';
import '../core/services/image_cleaner_service.dart';
import '../core/services/gemini_service.dart';
import '../core/services/prescription_parser.dart';
import '../core/services/skin_photo_quality_checker.dart';
import '../core/services/skin_scan_service.dart';
import '../core/services/connectivity_service.dart';
import '../core/services/tts_service.dart';
import '../data/models/models.dart';
import '../services/ai_insights_firestore_service.dart';
import '../services/chat_firestore_service.dart';
import '../services/skin_scan_firestore_service.dart';
import '../services/vitals_firestore_service.dart';
import 'profile_provider.dart';
import 'reminder_provider.dart';
import 'dart:convert';

class ChatProvider extends ChangeNotifier {
  ChatProvider({this.reminderEngine, this.profileProvider}) {
    _initForCurrentUser();
    FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user?.uid == _initializedForUid) return;
      _initForCurrentUser();
    });
  }

  String? _initializedForUid;
  bool _initializing = false;
  final ReminderProvider? reminderEngine;
  final ProfileProvider? profileProvider;
  final messages = <ChatMessage>[];
  bool typing = false;
  bool learnFromData = true;

  // Speaks MedAI's replies aloud on-device (free, offline TTS) so voice
  // input ("hold mic to talk") can be a real two-way conversation instead
  // of talk-in / read-out. Off by default — a text chat that suddenly
  // starts talking would surprise anyone who didn't ask for it.
  bool voiceReplyEnabled = false;
  final pendingAttachments = <ChatAttachment>[];
  bool recording = false;
  bool transcribing = false;
  String? currentConversationId;
  List<ChatConversationSummary> conversations = [];
  bool loadingConversations = false;

  // Holds the user's message so "Retry" can pick up exactly where it left
  // off after a genuine connectivity failure, instead of the user having
  // to retype everything (including re-attaching photos).
  String? _lastFailedText;
  List<ChatAttachment>? _lastFailedAttachments;
  static const _retryLabel = 'Retry my last message';

  Future<void> _initForCurrentUser() async {
    if (_initializing) return;
    _initializing = true;
    messages.clear();
    currentConversationId = null;
    pendingAttachments.clear();
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

  Future<void> loadConversations() async {
    conversations = await ChatFirestoreService.instance.fetchConversations();
    notifyListeners();
  }

  Future<void> startNewConversation() async {
    messages.clear();
    pendingAttachments.clear();
    final id = await ChatFirestoreService.instance.createConversation();
    currentConversationId = id;
    final greeting = ChatMessage(
      role: ChatRole.ai,
      text: learnFromData
          ? "Hi! I'm MedAI. I can scan prescriptions and help you set reminders. How can I help you today?"
          : "Hi! How can I help you today?",
      personalized: learnFromData,
    );
    messages.add(greeting);
    notifyListeners();
    await _persist(greeting);
  }

  Future<void> openConversation(String id) async {
    currentConversationId = id;
    messages.clear();
    final history = await ChatFirestoreService.instance.fetchMessages(id);
    messages.addAll(history);
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

  Future<void> send(String text) async {
    // Cut off any reply MedAI is still speaking — the user sending a new
    // message means they're done listening to the last one.
    TtsService.instance.stop();
    final t = text.trim();

    // The offline card's "Retry" chip routes back here (same as any other
    // quick-reply) — special-case it to replay the original failed
    // message instead of sending the literal button label to the AI.
    if (t == _retryLabel && _lastFailedText != null) {
      final retryText = _lastFailedText!;
      final retryAttachments = _lastFailedAttachments ?? const <ChatAttachment>[];
      _lastFailedText = null;
      _lastFailedAttachments = null;
      await _routeReply(retryText, retryAttachments);
      return;
    }

    if (t.isEmpty && pendingAttachments.isEmpty) return;
    final attachments = [...pendingAttachments];
    pendingAttachments.clear();
    notifyListeners();
    await _sendUser(t, attachments);
    await _routeReply(t, attachments);
  }

  Future<void> _routeReply(String text, List<ChatAttachment> attachments) async {
    // Hardcoded safety net — runs before anything else (before even the
    // connectivity check, since this needs no network) and before the AI
    // ever gets a turn. A model can hedge, get rate-limited, or just
    // answer conversationally; a possible emergency shouldn't wait on any
    // of that.
    if (_looksLikeEmergency(text)) {
      await _reply(const ChatMessage(
        role: ChatRole.ai,
        card: ChatCardType.sos,
        text: "If you're in immediate danger, call your local emergency "
            "number now (agar khatra hai to abhi apni local emergency "
            "helpline ko call karein). Tap this card to open Emergency SOS.",
      ));
    }

    typing = true;
    notifyListeners();
    // One connectivity check covers every reply path below (Groq, Gemini
    // prescription/image scans) — a real DNS lookup, not just the OS's
    // wifi-connected flag, so a phone on wifi-with-no-internet doesn't
    // silently hang on a request that will never complete.
    if (!await ConnectivityService.hasConnection()) {
      _lastFailedText = text;
      _lastFailedAttachments = attachments;
      await _reply(ChatMessage(
        role: ChatRole.ai,
        card: ChatCardType.quickReplies,
        text: "Looks like you're offline. Reconnect and tap below to pick "
            "up right where you left off.",
        quickReplies: const [_retryLabel],
      ));
      return;
    }

    // Fire-and-forget — completely separate from the main reply call, so
    // it can never consume the model's turn and leave the user with a
    // generic filler line instead of a real answer (see chat history for
    // why this used to happen when insight-noting shared a call).
    if (learnFromData && text.trim().isNotEmpty) {
      unawaited(_noteInsightIfWorthwhile(text));
    }

    ChatAttachment? rxPhoto;
    ChatAttachment? skinPhoto;
    final generalImage = attachments.where((a) => a.type == AttachmentType.image).toList();
    final generalFiles = attachments.where((a) => a.type == AttachmentType.file).toList();

    for (final a in attachments) {
      if (a.intent == AttachmentIntent.prescription) rxPhoto = a;
      if (a.intent == AttachmentIntent.skin) skinPhoto = a;
    }
    if (rxPhoto != null) {
      await _replyFromPrescriptionScan(rxPhoto);
      return;
    }
    if (skinPhoto != null) {
      await _replyFromSkinCheck(skinPhoto);
      return;
    }
    if (generalImage.isNotEmpty) {
      await _replyFromGeneralImage(generalImage.first, text);
      return;
    }
    if (generalFiles.isNotEmpty) {
      await _replyFromGeneralFile(generalFiles.first, text);
      return;
    }
    await _replyFromGroq();
  }

  Future<void> _replyFromSkinCheck(ChatAttachment photo) async {
    typing = true;
    notifyListeners();
    try {
      final path = photo.filePath!;

      final quality = await SkinPhotoQualityChecker.check(path);
      if (quality != SkinPhotoQuality.ok) {
        typing = false;
        await _reply(ChatMessage(
          role: ChatRole.ai,
          text: SkinPhotoQualityChecker.message(quality),
        ));
        return;
      }

      final result = await SkinScanService.analyze(path);
      typing = false;

      if (result.metrics.isEmpty) {
        await _reply(const ChatMessage(
          role: ChatRole.ai,
          text: "MedAI couldn't get a reading from that photo. Please try again with a clear, well-lit photo of your face.",
        ));
        return;
      }

      final summaryLines = result.metrics
          .map((m) => "• ${m.label}: ${(m.score * 100).round()}%")
          .join('\n');
      final summary = "Here's what MedAI found:\n\n$summaryLines\n\n"
          "This is a general visual estimate, not a diagnosis.";

      // Save to history so progress can be tracked over time — done in the
      // background; a save failure shouldn't block showing the result.
      SkinScanFirestoreService.instance.saveScan(SkinScanRecord(
        metrics: {for (final m in result.metrics) m.label: m.score},
        imagePath: path,
        date: DateTime.now(),
      ));

      await _reply(ChatMessage(
        role: ChatRole.ai,
        card: ChatCardType.skin,
        text: summary,
        skinScanJson: jsonEncode({
          'metrics': result.metrics
              .map((m) => {'label': m.label, 'score': m.score})
              .toList(),
        }),
        imagePath: path,
        personalized: learnFromData,
      ));
    } catch (e) {
      typing = false;
      debugPrint('[ChatProvider] Skin scan FAILED: $e');
      await _reply(const ChatMessage(
        role: ChatRole.ai,
        text: "Couldn't complete the skin scan — the analysis server "
            "might be waking up (this can take up to a minute on the "
            "first try). Please try again in a moment.",
      ));
    }
  }

  Future<void> sendHeartRateResult(double bpm) async {
    await _replyFromHeartRateResult(bpm);
  }

  Future<void> _replyFromHeartRateResult(double bpm) async {
    typing = true;
    notifyListeners();
    try {
      final reading = HeartRateReading(bpm: bpm);
      final profile = profileProvider?.profile;
      final contextLine = profile != null ? reading.personalizedContext(profile) : 'Estimated from camera — not a medical device';
      final summary = 'Heart rate: ${reading.bpm.round()} BPM\n'
          '${reading.zoneLabel}\n'
          '$contextLine\n'
          'Estimated from camera — not a medical device';

      await VitalsFirestoreService.instance.saveScan(bpm);

      typing = false;
      await _reply(ChatMessage(
        role: ChatRole.ai,
        card: ChatCardType.heartRate,
        text: summary,
        personalized: learnFromData,
      ));
    } catch (e) {
      typing = false;
      debugPrint('[ChatProvider] Heart rate result FAILED: $e');
      await _reply(const ChatMessage(
        role: ChatRole.ai,
        text: 'Could not save this heart-rate reading. Please try again.',
      ));
    }
  }

  Future<void> _replyFromPrescriptionScan(ChatAttachment photo) async {
    typing = true;
    notifyListeners();
    try {
      final String inputPath = photo.filePath!;
      final String? cleanedPath = await ImageCleanerService.cleanForVision(inputPath);
      final String processPath = cleanedPath ?? inputPath;

      final jsonOutput = await GeminiService.readPrescription(processPath);
      typing = false;
      final meds = getMedsFromOcr(jsonOutput);

      final medList = meds.map((m) => "• ${m.name} (${m.dose})").join("\n");
      final summary = "I identified ${meds.length} medications:\n\n$medList";

      await _reply(ChatMessage(
        role: ChatRole.ai,
        card: ChatCardType.prescription,
        text: summary,
        ocrText: jsonOutput,
        imagePath: processPath,
        personalized: learnFromData,
      ));
    } catch (e) {
      typing = false;
      await _reply(const ChatMessage(role: ChatRole.ai, text: "Scanning error. Please ensure the photo is clear."));
    }
  }

  Future<void> _replyFromGeneralImage(ChatAttachment photo, String userText) async {
    typing = true;
    notifyListeners();
    try {
      final imagePath = photo.filePath;
      if (imagePath == null || imagePath.isEmpty) {
        typing = false;
        await _reply(const ChatMessage(
          role: ChatRole.ai,
          text: 'I can look at the image once it is available. Please try again or ask a question about the photo.',
        ));
        return;
      }

      final prompt = (userText.trim().isNotEmpty)
          ? userText.trim()
          : 'Describe what is in this image and tell me what it likely is, including any important details.';
      final answer = await GeminiService.describeImage(imagePath, prompt: prompt);
      typing = false;
      await _reply(ChatMessage(
        role: ChatRole.ai,
        text: answer,
        personalized: learnFromData,
      ));
    } catch (e) {
      typing = false;
      debugPrint('[ChatProvider] General image analysis failed: $e');
      await _reply(const ChatMessage(
        role: ChatRole.ai,
        text: 'I couldn’t reliably read that image. Please upload a clearer photo or ask a specific question about what you want checked.',
      ));
    }
  }

  Future<void> _replyFromGeneralFile(ChatAttachment file, String userText) async {
    typing = true;
    notifyListeners();
    try {
      final filePath = file.filePath;
      if (filePath == null || filePath.isEmpty) {
        typing = false;
        await _reply(const ChatMessage(
          role: ChatRole.ai,
          text: 'I can read this document once the file is available. Please try attaching it again.',
        ));
        return;
      }

      final prompt = userText.trim().isNotEmpty
          ? userText.trim()
          : 'Summarize what this document contains and flag anything that looks important.';

      final answer = await GeminiService.describeDocument(filePath, prompt: prompt);
      typing = false;
      await _reply(ChatMessage(role: ChatRole.ai, text: answer, personalized: learnFromData));
    } on UnsupportedDocumentException catch (e) {
      typing = false;
      await _reply(ChatMessage(role: ChatRole.ai, text: e.message));
    } catch (e) {
      typing = false;
      debugPrint('[ChatProvider] Document analysis failed: $e');
      await _reply(const ChatMessage(
        role: ChatRole.ai,
        text: "I couldn't read that document just now — it may be a scanned "
            "image with no selectable text, or the analysis server is "
            "waking up. Please try again in a moment, or send a clear "
            "photo of the specific page instead.",
      ));
    }
  }

  Future<void> _replyFromGroq() async {
    typing = true;
    notifyListeners();
    try {
      final relevantMessages = messages.where((m) => m.text.isNotEmpty).toList();
      final chatHistory = relevantMessages
          .skip(relevantMessages.length > 10 ? relevantMessages.length - 10 : 0)
          .map((m) => {
        'role': m.role == ChatRole.user ? 'user' : 'assistant',
        'content': m.text,
      })
          .toList();

      String systemPrompt = "You are MedAI, a calm, professional health assistant. "
          "Answer like a thoughtful medical AI: clear, grounded, careful, and honest. "
          "Never invent facts, never guess a diagnosis, and never present a hunch as certainty. "
          "If the user sends a random photo, object, document, or anything not clearly medical, respond as a helpful general assistant: describe what you can observe, explain the likely purpose or meaning, ask clarifying questions if needed, and avoid overclaiming. "
          "For medical questions, separate facts from uncertainty and encourage professional care when appropriate. "
          "For all questions, give concise but useful answers, prioritize what is safe and realistic, and say what is uncertain instead of pretending certainty. "
          "Be practical, confident only when evidence supports it, and never be overly verbose. "
          "Use a natural, professional tone like a premium health companion app, not a robotic script.";

      if (learnFromData && profileProvider != null) {
        final p = profileProvider!.profile;
        systemPrompt += "\n\nUSER HEALTH PROFILE CONTEXT:"
            "\n- Name: ${p.name}"
            "\n- DOB: ${p.dob}";
        if (p.weightLb > 0) {
          systemPrompt += "\n- Weight: ${p.weightLb} lb";
        }
        if (p.heightIn > 0) {
          systemPrompt += "\n- Height: ${p.heightLabel}";
        }
        systemPrompt += "\n- Conditions: ${p.conditions.join(', ')}"
            "\n- Allergies: ${p.allergies.join(', ')}"
            "\n- Medications: ${p.medications.join(', ')}";
      }

      systemPrompt += "\n\nBEHAVIOR RULES:"
          "\n- Be professional and conversational, not robotic."
          "\n- When the user shares a non-medical image or general item, respond like a capable assistant: summarize the visible content, explain what it likely is, and ask a focused follow-up if necessary."
          "\n- Do not guess diagnoses from random photos or vague descriptions."
          "\n- If the evidence is limited, say exactly what is uncertain and what additional context would help."
          "\n- Use plain language and avoid definitive claims without enough evidence."
          "\n- If a symptom, photo, or document suggests a possible medical issue, give general educational guidance and suggest a clinician or urgent care when appropriate."
          "\n\nCURRENT ACTIVE REMINDERS: ${_remindersSummaryForPrompt()}"
          "\nREMINDER RULES: When the user asks to set a medicine reminder, "
          "you need a real TIME (and ideally how many times a day) before calling add_reminder. "
          "If the user's message already states a clear time (e.g. 'at 9 PM', 'after breakfast and dinner'), "
          "go ahead and call add_reminder directly — don't ask needless questions for something already answered. "
          "But if the time or frequency is missing or ambiguous, do NOT guess a time and do NOT call add_reminder. "
          "Instead call ask_reminder_details with a short, friendly question and 2-4 short suggested "
          "replies as options (e.g. specific times, or frequencies like 'Once daily', 'Twice daily'), "
          "so the user can just tap one instead of typing."
          "\n- MULTI-DOSE MEDICINES: if the medicine is taken more than once a day and the user gives (or "
          "you can reasonably infer, e.g. 'twice daily' -> morning and evening) more than one clock time, "
          "pass ALL of those times to add_reminder's time field as a single comma-separated string, e.g. "
          "'8:00 AM, 8:00 PM' for twice daily or '8:00 AM, 2:00 PM, 8:00 PM' for three times daily — this "
          "creates one alarm per dose. Never drop a dose time. If frequency is known ('twice daily') but "
          "the actual clock times are not, ask via ask_reminder_details rather than guessing them."
          "\n- BEFORE creating a reminder, check CURRENT ACTIVE REMINDERS above — if the same medicine at "
          "essentially the same time already exists, tell the user it's already set instead of creating a duplicate."
          "\n- To remove a reminder the user no longer wants, call cancel_reminder with its title (match it "
          "against CURRENT ACTIVE REMINDERS above)."
          "\n- To change an existing reminder's time, dose, schedule, or instructions, call update_reminder "
          "with its title and only the fields that changed."
          "\n- If the user asks what reminders they have, call list_reminders instead of describing "
          "CURRENT ACTIVE REMINDERS yourself — it returns a clean, accurate formatted list.";

      // No note_health_insight in the tools offered to the main reply
      // call — that's handled by a fully separate, non-blocking call (see
      // _noteInsightIfWorthwhile) so it can never consume a turn and leave
      // the user with a blank/generic reply instead of a real answer.
      final tools = [
        {
          'type': 'function',
          'function': {
            'name': 'add_reminder',
            'description': 'Add a recurring medicine reminder/alarm for the user. Only call this once you have real, specific time(s) — never a guessed one.',
            'parameters': {
              'type': 'object',
              'properties': {
                'title': {'type': 'string', 'description': 'The name of the medicine'},
                'dose': {'type': 'string', 'description': 'The dose amount (e.g. 500mg)'},
                'time': {'type': 'string', 'description': 'The exact clock time in "H:MM AM/PM" format, e.g. "9:00 AM" or "10:30 PM". Always include minutes, even if :00. For a medicine taken more than once a day, pass ALL dose times as one comma-separated string, e.g. "8:00 AM, 8:00 PM" — never just one time for a multi-dose medicine.'},
                'schedule': {'type': 'string', 'description': 'Frequency (e.g. Daily, Weekdays)'},
                'instructions': {'type': 'string', 'description': 'e.g. after food'},
              },
              'required': ['title', 'time'],
            },
          },
        },
        {
          'type': 'function',
          'function': {
            'name': 'ask_reminder_details',
            'description': 'Ask the user for a missing detail (usually time or frequency) needed to set a reminder, giving them short tappable suggestions instead of guessing.',
            'parameters': {
              'type': 'object',
              'properties': {
                'question': {'type': 'string', 'description': 'A short, natural question, e.g. "What time should I remind you?"'},
                'options': {
                  'type': 'array',
                  'items': {'type': 'string'},
                  'description': '2-4 short tappable suggestions, e.g. ["8:00 AM", "9:00 PM"] or ["Once daily", "Twice daily", "3 times daily"].',
                },
              },
              'required': ['question', 'options'],
            },
          },
        },
        {
          'type': 'function',
          'function': {
            'name': 'list_reminders',
            'description': 'Show the user their current active reminders as a clean formatted list. Call this whenever they ask what reminders/alarms they have.',
            'parameters': {'type': 'object', 'properties': {}},
          },
        },
        {
          'type': 'function',
          'function': {
            'name': 'cancel_reminder',
            'description': 'Cancel/delete an existing reminder the user no longer wants.',
            'parameters': {
              'type': 'object',
              'properties': {
                'title': {'type': 'string', 'description': 'The reminder\'s medicine title, matched against CURRENT ACTIVE REMINDERS.'},
              },
              'required': ['title'],
            },
          },
        },
        {
          'type': 'function',
          'function': {
            'name': 'update_reminder',
            'description': 'Change one or more fields (time, dose, schedule, instructions) of an existing reminder.',
            'parameters': {
              'type': 'object',
              'properties': {
                'title': {'type': 'string', 'description': 'The existing reminder\'s title to find and update, matched against CURRENT ACTIVE REMINDERS.'},
                'new_time': {'type': 'string', 'description': 'New clock time(s), same format as add_reminder\'s time field. Omit if unchanged.'},
                'new_dose': {'type': 'string', 'description': 'New dose amount. Omit if unchanged.'},
                'new_schedule': {'type': 'string', 'description': 'New frequency, e.g. Daily, Weekdays. Omit if unchanged.'},
                'new_instructions': {'type': 'string', 'description': 'New instructions, e.g. after food. Omit if unchanged.'},
              },
              'required': ['title'],
            },
          },
        },
      ];

      final result0 = await _consumeGroqStream(systemPrompt: systemPrompt, history: chatHistory, tools: tools);
      final result = result0.result;
      final streamIndex = result0.streamIndex;

      // Handle Automation (Tool Calls)
      if (result.hasToolCalls && reminderEngine != null) {
        // The branches below build their own properly-typed card message
        // (quick replies / reminder-added / plain text) — drop the
        // streamed placeholder bubble first so it isn't left behind
        // alongside it.
        if (streamIndex != null) {
          messages.removeAt(streamIndex);
          notifyListeners();
        }
        final addedReminders = <Reminder>[];
        String? clarifyQuestion;
        List<String>? clarifyOptions;
        String? duplicateSkipped;
        bool listRequested = false;
        final cancelledTitles = <String>[];
        final updatedTitles = <String>[];
        final notFoundQueries = <String>[];

        for (final tc in result.toolCalls!) {
          if (tc.name == 'add_reminder') {
            final args = tc.arguments;
            final title = (args['title'] ?? 'Medicine').toString();
            final normalizedTime = _normalizeTimesString(args['time']?.toString());
            final schedule = (args['schedule'] ?? 'Daily').toString();

            // Duplicate guard: if MedAI (or the user re-phrasing) tries to
            // create a reminder that already exists — same title and same
            // time(s) — skip creating a second copy rather than silently
            // doubling up alarms for the same dose.
            final dup = reminderEngine!.reminders.any((r) =>
            r.enabled &&
                _isSimilarInsightText(r.title, title) &&
                r.time == normalizedTime);
            if (dup) {
              duplicateSkipped = title;
              continue;
            }

            final r = Reminder(
              title: title,
              dose: args['dose'] ?? '',
              time: normalizedTime,
              schedule: schedule,
              instructions: args['instructions'] ?? '',
              addedBy: 'MedAI',
            );
            await reminderEngine!.add(r);
            addedReminders.add(r);
          } else if (tc.name == 'ask_reminder_details') {
            final args = tc.arguments;
            clarifyQuestion = args['question']?.toString();
            final rawOptions = args['options'];
            if (rawOptions is List) {
              clarifyOptions = rawOptions.map((o) => o.toString()).toList();
            }
          } else if (tc.name == 'list_reminders') {
            listRequested = true;
          } else if (tc.name == 'cancel_reminder') {
            final args = tc.arguments;
            final query = args['title']?.toString() ?? '';
            final match = _findReminderByTitle(query);
            if (match != null) {
              await reminderEngine!.remove(match);
              cancelledTitles.add(match.title);
            } else {
              notFoundQueries.add(query);
            }
          } else if (tc.name == 'update_reminder') {
            final args = tc.arguments;
            final query = args['title']?.toString() ?? '';
            final match = _findReminderByTitle(query);
            if (match != null) {
              final newTimeRaw = args['new_time']?.toString();
              await reminderEngine!.update(
                match,
                time: newTimeRaw != null && newTimeRaw.trim().isNotEmpty
                    ? _normalizeTimesString(newTimeRaw)
                    : null,
                dose: args['new_dose']?.toString(),
                schedule: args['new_schedule']?.toString(),
                instructions: args['new_instructions']?.toString(),
              );
              updatedTitles.add(match.title);
            } else {
              notFoundQueries.add(query);
            }
          }
        }

        if (clarifyQuestion != null && (clarifyOptions?.isNotEmpty ?? false)) {
          // Ask via tappable suggestions instead of guessing a time/frequency.
          await _reply(ChatMessage(
            role: ChatRole.ai,
            card: ChatCardType.quickReplies,
            text: clarifyQuestion,
            quickReplies: clarifyOptions,
            personalized: learnFromData,
          ));
          return;
        }

        if (listRequested) {
          await _reply(_buildReminderListMessage());
          return;
        }

        if (cancelledTitles.isNotEmpty || updatedTitles.isNotEmpty || notFoundQueries.isNotEmpty) {
          final parts = <String>[];
          if (cancelledTitles.isNotEmpty) {
            parts.add(cancelledTitles.length == 1
                ? 'Cancelled the ${cancelledTitles.first} reminder.'
                : 'Cancelled ${cancelledTitles.length} reminders: ${cancelledTitles.join(', ')}.');
          }
          if (updatedTitles.isNotEmpty) {
            parts.add(updatedTitles.length == 1
                ? 'Updated the ${updatedTitles.first} reminder.'
                : 'Updated ${updatedTitles.length} reminders: ${updatedTitles.join(', ')}.');
          }
          if (notFoundQueries.isNotEmpty) {
            parts.add('Couldn\'t find a reminder matching "${notFoundQueries.join(', ')}" — '
                'check the exact name on your Reminders screen.');
          }
          await _reply(ChatMessage(role: ChatRole.ai, text: parts.join(' '), personalized: learnFromData));
          return;
        }

        if (addedReminders.isEmpty && duplicateSkipped != null) {
          await _reply(ChatMessage(
            role: ChatRole.ai,
            text: 'You already have a reminder set for $duplicateSkipped at that time — '
                'I didn\'t create a duplicate.',
            personalized: learnFromData,
          ));
          return;
        }

        String responseText = result.content ?? '';
        if (addedReminders.isNotEmpty && responseText.isEmpty) {
          responseText = addedReminders.length == 1
              ? '${addedReminders.first.title} reminder set for ${addedReminders.first.time}.'
              : 'Set ${addedReminders.length} reminders.';
        }
        // If the ONLY thing the model did was the silent note_health_insight
        // call, it likely spent the whole turn on that tool call and never
        // produced real reply text (typical for tool-calling models — content
        // and tool_calls rarely come back together). Ask again, without
        // tools this time, so the user gets an actual answer to what they
        // said instead of a generic filler line every single message.
        if (responseText.isEmpty && addedReminders.isEmpty && clarifyQuestion == null) {
          try {
            responseText = await GroqService.chat(systemPrompt: systemPrompt, history: chatHistory);
          } catch (_) {
            // fall through to the generic line below if this retry also fails
          }
          if (responseText.trim().isEmpty) {
            responseText = "Got it, thanks for sharing that.";
          }
        }

        if (addedReminders.isNotEmpty) {
          await _reply(ChatMessage(
            role: ChatRole.ai,
            card: ChatCardType.reminderAdded,
            text: responseText,
            personalized: learnFromData,
          ));
        } else {
          await _reply(ChatMessage(role: ChatRole.ai, text: responseText, personalized: learnFromData));
        }
      } else {
        final finalText = result.content ?? '';
        if (streamIndex != null) {
          // Content already streamed in live — just drop the streaming
          // indicator and persist the final version.
          messages[streamIndex] = messages[streamIndex].copyWith(
            text: finalText.isNotEmpty ? finalText : messages[streamIndex].text,
            streaming: false,
          );
          notifyListeners();
          _speakIfEnabled(messages[streamIndex]);
          await _persist(messages[streamIndex]);
        } else {
          await _reply(ChatMessage(role: ChatRole.ai, text: finalText, personalized: learnFromData));
        }
      }

    } catch (e) {
      typing = false;
      // Clean up a partially-streamed bubble if the connection dropped
      // mid-response, rather than leaving a stuck "still typing" message.
      if (messages.isNotEmpty && messages.last.streaming) {
        messages.removeLast();
      }
      debugPrint('[ChatProvider] Groq Error: $e');
      String errorMsg = "I'm having trouble responding. Please check your internet.";
      if (e.toString().contains('429')) {
        errorMsg = "Too many messages too fast — please wait a moment.";
      }
      await _reply(ChatMessage(role: ChatRole.ai, text: errorMsg));
    }
  }

  /// Drains a [GroqService.chatWithToolsStream] call, live-updating a
  /// growing placeholder bubble in [messages] as text arrives. Returns the
  /// final assembled result plus the index of that placeholder bubble (or
  /// null if the reply was tool-calls-only with no streamed text), so the
  /// caller can either finalize it in place or discard it in favor of a
  /// structured card (reminder/quick-reply) built from the tool calls.
  Future<({GroqChatResult result, int? streamIndex})> _consumeGroqStream({
    required String systemPrompt,
    required List<Map<String, String>> history,
    required List<Map<String, dynamic>>? tools,
  }) async {
    GroqChatResult result = GroqChatResult(content: null, toolCalls: null);
    int? streamIndex;

    await for (final event in GroqService.chatWithToolsStream(
      systemPrompt: systemPrompt,
      history: history,
      tools: tools,
    )) {
      if (event.isDone) {
        result = event.result!;
        break;
      }
      final text = event.textSoFar ?? '';
      if (text.isEmpty) continue;
      typing = false; // first tokens arrived — swap the "typing…" dots for live text
      if (streamIndex == null) {
        messages.add(ChatMessage(role: ChatRole.ai, text: text, streaming: true, personalized: learnFromData));
        streamIndex = messages.length - 1;
      } else {
        messages[streamIndex] = messages[streamIndex].copyWith(text: text);
      }
      notifyListeners();
    }

    return (result: result, streamIndex: streamIndex);
  }

  /// Best-effort match for "cancel my metformin reminder" style requests —
  /// exact title match first, then a loose contains-either-way match, so
  /// the AI doesn't need the user's wording to exactly match what's stored.
  Reminder? _findReminderByTitle(String query) {
    if (reminderEngine == null) return null;
    final q = query.toLowerCase().trim();
    if (q.isEmpty) return null;

    for (final r in reminderEngine!.reminders) {
      if (r.title.toLowerCase().trim() == q) return r;
    }
    for (final r in reminderEngine!.reminders) {
      final t = r.title.toLowerCase().trim();
      if (t.contains(q) || q.contains(t)) return r;
    }
    return null;
  }

  /// Plain-text summary of the user's active reminders, used both for the
  /// `list_reminders` tool call and to give the main reply call visibility
  /// into what already exists (so it can reference exact titles for
  /// cancel/update instead of guessing, and avoid proposing a reminder
  /// that's already there).
  String _remindersSummaryForPrompt() {
    final active = reminderEngine?.reminders.where((r) => r.enabled).toList() ?? const <Reminder>[];
    if (active.isEmpty) return 'none';
    return active
        .map((r) => '"${r.title}" ${r.dose.isNotEmpty ? '(${r.dose}) ' : ''}at ${r.time}, ${r.schedule}')
        .join('; ');
  }

  ChatMessage _buildReminderListMessage() {
    final active = reminderEngine?.reminders.where((r) => r.enabled).toList() ?? const <Reminder>[];
    if (active.isEmpty) {
      return ChatMessage(
        role: ChatRole.ai,
        text: "You don't have any active reminders yet. Tell me a medicine, dose, and time and I'll set one up.",
        personalized: learnFromData,
      );
    }
    final lines = active
        .map((r) => '• ${r.title}${r.dose.isNotEmpty ? ' (${r.dose})' : ''} — ${r.time} · ${r.schedule}')
        .join('\n');
    return ChatMessage(
      role: ChatRole.ai,
      text: 'Here are your active reminders:\n\n$lines',
      personalized: learnFromData,
    );
  }

  /// Converts whatever time format the AI happens to return — "10 PM",
  /// "22:00", "10:00pm", "10:00 PM" — into the exact "H:MM AM/PM" shape
  /// the alarm scheduler (`NotificationService._parseTimeOfDay`) requires.
  /// Without this, a reminder can be saved and show up on the Reminders
  /// screen while its alarm silently never gets scheduled, because the
  /// scheduler's format check is strict and the AI's wording isn't
  /// guaranteed to match it exactly.
  String _normalizeTimeString(String? raw) {
    const fallback = '9:00 AM';
    if (raw == null || raw.trim().isEmpty) return fallback;
    final text = raw.trim().toUpperCase();

    // "H:MM AM/PM" or "H:MM" with no space before AM/PM, e.g. "10:00PM".
    final withMinutes =
    RegExp(r'^(\d{1,2}):(\d{1,2})\s*(AM|PM)?$').firstMatch(text);
    if (withMinutes != null) {
      var hour = int.tryParse(withMinutes.group(1)!) ?? 9;
      final minute = int.tryParse(withMinutes.group(2)!) ?? 0;
      final period = withMinutes.group(3);
      if (period == null) {
        // No AM/PM given — treat as 24-hour clock, e.g. "22:00".
        if (hour > 23 || minute > 59) return fallback;
        final isPm = hour >= 12;
        final displayHour =
        hour % 12 == 0 ? 12 : hour % 12; // 0/12 -> 12, 13 -> 1, etc.
        return '$displayHour:${minute.toString().padLeft(2, '0')} '
            '${isPm ? 'PM' : 'AM'}';
      }
      if (hour > 12 || minute > 59) return fallback;
      if (hour == 0) hour = 12;
      return '$hour:${minute.toString().padLeft(2, '0')} $period';
    }

    // "H AM/PM" — hour only, no minutes, e.g. "10 PM".
    final hourOnly = RegExp(r'^(\d{1,2})\s*(AM|PM)$').firstMatch(text);
    if (hourOnly != null) {
      final hour = int.tryParse(hourOnly.group(1)!) ?? 9;
      final period = hourOnly.group(2)!;
      if (hour < 1 || hour > 12) return fallback;
      return '$hour:00 $period';
    }

    // Nothing recognized — fall back to a safe default rather than saving
    // an unparseable time that would silently never ring.
    return fallback;
  }

  /// Same idea as [_normalizeTimeString] but for reminders with more than
  /// one dose a day. `NotificationService.scheduleReminder` already knows
  /// how to schedule a separate alarm for each comma-separated time in
  /// `Reminder.time` (e.g. "8:00 AM, 8:00 PM") — the manual add-reminder
  /// form already relies on this. The AI path used to funnel everything
  /// through the single-time-only normalizer above, so a message like
  /// "twice daily, 8am and 8pm" would silently keep only one dose (or
  /// fall back to 9:00 AM) and the second dose's alarm would just never
  /// get created. This splits on commas/"and", normalizes each piece, and
  /// rejoins — so multi-dose reminders actually get every alarm they need.
  String _normalizeTimesString(String? raw) {
    if (raw == null || raw.trim().isEmpty) return _normalizeTimeString(raw);

    final pieces = raw
        .split(RegExp(r',|\band\b', caseSensitive: false))
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();

    if (pieces.isEmpty) return _normalizeTimeString(raw);
    if (pieces.length == 1) return _normalizeTimeString(pieces.first);

    final normalized = pieces.map(_normalizeTimeString).toSet().toList();
    return normalized.join(', ');
  }


  Future<void> _sendUser(String text, List<ChatAttachment> attachments) async {
    final message = ChatMessage(role: ChatRole.user, text: text, attachments: attachments);
    messages.add(message);
    notifyListeners();
    await _persist(message);
  }

  Future<void> _reply(ChatMessage message) async {
    typing = false;
    messages.add(message);
    notifyListeners();
    _speakIfEnabled(message);
    await _persist(message);
  }

  Future<void> _persist(ChatMessage message) async {
    if (currentConversationId != null) {
      ChatFirestoreService.instance.saveMessage(currentConversationId!, message).catchError((_) {
        return ChatMessage(role: ChatRole.ai, text: '');
      });
    }
  }

  void toggleLearn() {
    learnFromData = !learnFromData;
    notifyListeners();
  }

  void toggleVoiceReply() {
    voiceReplyEnabled = !voiceReplyEnabled;
    if (!voiceReplyEnabled) TtsService.instance.stop();
    notifyListeners();
  }

  /// Speaks a finished AI reply aloud when voice replies are on. Never
  /// called on interim streaming deltas — only once a message's text is
  /// final — so MedAI doesn't try to narrate half-formed sentences.
  void _speakIfEnabled(ChatMessage message) {
    if (!voiceReplyEnabled) return;
    if (message.role != ChatRole.ai) return;
    if (message.text.trim().isEmpty) return;
    unawaited(TtsService.instance.speak(message.text));
  }

  void startRecording() {
    // Don't let MedAI's own voice talk over the user while they're
    // recording their next message.
    TtsService.instance.stop();
    recording = true;
    notifyListeners();
  }

  Future<void> stopRecording({required int seconds, bool cancelled = false, String? filePath}) async {
    recording = false;
    notifyListeners();
    if (cancelled || seconds < 1 || filePath == null) return;

    transcribing = true;
    notifyListeners();

    try {
      final transcript = await GroqService.transcribeAudio(filePath);
      transcribing = false;

      if (transcript.trim().isNotEmpty) {
        // Only the recognized text goes into the chat — the voice note
        // itself is not attached or shown.
        await send(transcript.trim());
      } else {
        notifyListeners();
        // Nothing recognized — silently drop it, nothing to send.
      }
    } catch (e) {
      transcribing = false;
      notifyListeners();
    }
  }

  Future<void> deleteConversation(String id) async {
    try {
      final history = await ChatFirestoreService.instance.fetchMessages(id);
      final pathsToDelete = history
          .map((m) => m.imagePath)
          .where((p) => p != null)
          .cast<String>()
          .toSet();

      for (final path in pathsToDelete) {
        try {
          final file = File(path);
          if (await file.exists()) {
            await file.delete();
          }
        } catch (e) {
          debugPrint('[ChatProvider] Failed to delete photo at $path: $e');
        }
      }
    } catch (e) {
      debugPrint('[ChatProvider] Error during image cleanup for conversation $id: $e');
    }

    await ChatFirestoreService.instance.deleteConversation(id);
    await loadConversations();
    if (currentConversationId == id) await startNewConversation();
  }

  Future<void> noteRemindersAdded(int count) async {
    await _reply(ChatMessage(role: ChatRole.ai, text: 'Added $count reminders.', personalized: learnFromData));
  }

  /// Hardcoded (not AI-judged) emergency detection — deliberately dumb and
  /// keyword-based rather than model-based, so it can never be talked out
  /// of firing by phrasing, and works even if the AI call itself fails.
  /// Some categories (stroke, unconsciousness, severe allergic reaction,
  /// overdose, active self-harm, uncontrolled bleeding) are unambiguous
  /// enough alone; others (chest symptoms, breathing trouble) only really
  /// signal an emergency in combination, which is why they need 2 distinct
  /// categories to hit before triggering.
  ///
  /// Each category includes English, Roman Urdu, and Urdu-script phrasings
  /// — a big share of users describe symptoms in Roman Urdu ("saans nahi
  /// aa rahi") or Urdu script (سانس نہیں آ رہی), and the English-only list
  /// this started with would never fire for them.
  static const Map<String, List<String>> _criticalAlone = {
    'stroke': [
      'face drooping', 'slurred speech', 'sudden confusion', 'sudden numbness', 'sudden severe headache',
      // Roman Urdu
      'chehra tirha', 'chehra jhuk gaya', 'zaban larkharana', 'zaban latpatana', 'achanak sunn', 'achanak confusion',
      // Urdu script
      'چہرہ ٹیڑھا', 'زبان لڑکھڑانا', 'اچانک سن ہونا', 'اچانک الجھن',
    ],
    'consciousness': [
      'unconscious', 'unresponsive', 'not breathing', 'no pulse', "passed out and won't wake",
      'behosh', 'be hosh', 'hosh nahi', 'hosh mein nahi', 'jaga nahi raha', 'jaga nahi rahi', 'saans nahi chal rahi', 'nabz nahi',
      'بے ہوش', 'ہوش میں نہیں', 'سانس نہیں چل رہی', 'نبض نہیں',
    ],
    'allergic': [
      'throat closing', 'anaphylaxis', 'severe allergic reaction', 'face and throat swelling',
      'gala band ho raha', 'gala sooj gaya', 'chehra aur gala soojna', 'shadeed allergy',
      'گلا بند ہو رہا', 'گلا سوج گیا', 'شدید الرجی',
    ],
    'overdose': [
      'overdose', 'took too many pills', 'swallowed poison',
      'zyada dawai kha li', 'zyada goliyan kha li', 'zeher kha liya', 'zeher pi liya',
      'زیادہ دوائی کھا لی', 'زہر کھا لیا', 'زہر پی لیا',
    ],
    'selfHarm': [
      'want to die', 'kill myself', 'suicidal', 'end my life', 'going to end it',
      'marna chahta hoon', 'marna chahti hoon', 'khudkushi', 'khud kushi', 'zindagi khatam karna', 'khud ko khatam',
      'مرنا چاہتا ہوں', 'مرنا چاہتی ہوں', 'خودکشی', 'زندگی ختم کرنا',
    ],
    'bleeding': [
      'severe bleeding', "won't stop bleeding", 'bleeding heavily', 'bleeding a lot',
      'shadeed khoon beh raha', 'khoon rukta nahi', 'bohat khoon beh raha', 'khoon bahut beh raha',
      'شدید خون بہہ رہا', 'خون رکتا نہیں', 'بہت خون بہہ رہا',
    ],
  };
  static const Map<String, List<String>> _criticalInCombo = {
    'chest': [
      'chest pain', 'chest pressure', 'chest tightness',
      'seene mein dard', 'seene me dard', 'seena jakar raha', 'seene mein bojh', 'seene me bojh',
      'سینے میں درد', 'سینہ جکڑنا', 'سینے میں بوجھ',
    ],
    'breathing': [
      'shortness of breath', "can't breathe", 'cant breathe', 'trouble breathing', 'difficulty breathing', 'gasping for air',
      'saans nahi aa rahi', 'saans nahi aa rahe', 'saans lene mein dushwari', 'saans phool rahi', 'saans phool rahi hai', 'dam ghut raha',
      'سانس نہیں آ رہی', 'سانس لینے میں دشواری', 'سانس پھول رہی', 'دم گھٹ رہا',
    ],
  };

  static bool _looksLikeEmergency(String text) {
    final lower = text.toLowerCase();
    bool hits(List<String> keywords) => keywords.any((k) => lower.contains(k));

    if (_criticalAlone.values.any(hits)) return true;
    final comboHits = _criticalInCombo.values.where(hits).length;
    return comboHits >= 2;
  }

  /// Runs completely independently of the main reply — its own dedicated
  /// (tools-only, no streaming) API call so it can never crowd out the
  /// user's actual answer. A missed or slightly-late insight is a much
  /// smaller problem than "Got it, thanks for sharing that" replacing a
  /// real reply, which is what happened when this shared a call with the
  /// main reply generation.
  Future<void> _noteInsightIfWorthwhile(String userText) async {
    try {
      if (!await ConnectivityService.hasConnection()) return;

      const insightSystemPrompt =
          "You silently extract a personalized health insight from ONE user message, for a "
          "health app's profile screen. Call note_health_insight ONLY if this message states a "
          "genuinely new symptom, ongoing health concern, or a clear preference about the "
          "user's own care. Do NOT call it for greetings, small talk, general knowledge "
          "questions, or vague/ambiguous messages. If nothing qualifies, don't call it at all — "
          "a missed insight is fine, a false one is not.";

      final result = await GroqService.chatWithTools(
        systemPrompt: insightSystemPrompt,
        history: [
          {'role': 'user', 'content': userText},
        ],
        tools: const [
          {
            'type': 'function',
            'function': {
              'name': 'note_health_insight',
              'description': 'Silently save a short, factual personalized insight.',
              'parameters': {
                'type': 'object',
                'properties': {
                  'category': {
                    'type': 'string',
                    'enum': ['symptom', 'concern', 'preference', 'note'],
                  },
                  'text': {
                    'type': 'string',
                    'description': 'Short (under 12 words), neutral, factual summary, e.g. "Reports mild headaches most mornings".',
                  },
                },
                'required': ['category', 'text'],
              },
            },
          },
        ],
      );

      if (!result.hasToolCalls) return;
      for (final tc in result.toolCalls!) {
        if (tc.name != 'note_health_insight') continue;
        final args = tc.arguments;
        final text = args['text']?.toString().trim() ?? '';
        if (text.isEmpty) continue;
        final category = AiInsightType.values.firstWhere(
              (e) => e.name == args['category']?.toString(),
          orElse: () => AiInsightType.note,
        );
        // Skip near-duplicates — without this, mentioning the same symptom
        // across a few messages would pile up as separate profile entries
        // instead of staying one clean fact.
        final existing = profileProvider?.aiInsights ?? const <AiInsight>[];
        final isDuplicate = existing.any((e) => e.type == category && _isSimilarInsightText(e.text, text));
        if (!isDuplicate) {
          await AiInsightsFirestoreService.instance.addInsight(AiInsight(
            type: category,
            text: text,
            createdAt: DateTime.now(),
            conversationId: currentConversationId,
          ));
        }
      }
    } catch (e) {
      debugPrint('[ChatProvider] insight extraction failed (non-fatal): $e');
    }
  }

  /// Loose "is this basically the same insight already saved" check —
  /// normalizes case/punctuation and treats one text containing the other
  /// as a duplicate, so "headache" and "mild headache most mornings"
  /// don't both get stored as separate facts.
  static bool _isSimilarInsightText(String a, String b) {
    String normalize(String s) =>
        s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9 ]'), '').trim();
    final na = normalize(a);
    final nb = normalize(b);
    if (na.isEmpty || nb.isEmpty) return false;
    if (na == nb) return true;
    return na.contains(nb) || nb.contains(na);
  }
}