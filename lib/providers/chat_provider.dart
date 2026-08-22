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
  final pendingAttachments = <ChatAttachment>[];
  bool recording = false;
  bool transcribing = false;
  String? currentConversationId;
  List<ChatConversationSummary> conversations = [];
  bool loadingConversations = false;

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
    final t = text.trim();
    if (t.isEmpty && pendingAttachments.isEmpty) return;
    final attachments = [...pendingAttachments];
    pendingAttachments.clear();
    notifyListeners();
    await _sendUser(t, attachments);
    await _routeReply(t, attachments);
  }

  Future<void> _routeReply(String text, List<ChatAttachment> attachments) async {
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
      final fileName = file.name;
      final prompt = userText.trim().isNotEmpty
          ? userText.trim()
          : 'Summarize what this document appears to contain and answer any likely questions about it.';
      final normalized = prompt.trim();
      typing = false;
      await _reply(ChatMessage(
        role: ChatRole.ai,
        text: normalized.isEmpty
            ? 'I can help with this document. Please ask a question about the page or upload a clearer photo/PDF scan.'
            : 'I can help with “$fileName” once it is readable. Please ask a specific question about the document, or upload a clearer photo/PDF if the page is too blurry or small.',
        personalized: learnFromData,
      ));
    } catch (e) {
      typing = false;
      await _reply(const ChatMessage(
        role: ChatRole.ai,
        text: 'I can help with this document once it is clearer or more readable. Please upload a sharper photo or ask a specific question.',
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
          "\nREMINDER RULES: When the user asks to set a medicine reminder, "
          "you need a real TIME (and ideally how many times a day) before calling add_reminder. "
          "If the user's message already states a clear time (e.g. 'at 9 PM', 'after breakfast and dinner'), "
          "go ahead and call add_reminder directly — don't ask needless questions for something already answered. "
          "But if the time or frequency is missing or ambiguous, do NOT guess a time and do NOT call add_reminder. "
          "Instead call ask_reminder_details with a short, friendly question and 2-4 short suggested "
          "replies as options (e.g. specific times, or frequencies like 'Once daily', 'Twice daily'), "
          "so the user can just tap one instead of typing.";

      if (learnFromData) {
        systemPrompt += "\n\nINSIGHT RULES: When the user mentions something worth remembering for "
            "future context — a recurring or new symptom, an ongoing health concern, or a clear "
            "preference about their care — call note_health_insight with a short (under 12 words), "
            "neutral, factual summary of it. Only call it for something genuinely new or notable in "
            "THIS message, never for small talk, never guessing, and never more than once per message. "
            "Do not mention that you saved anything — this happens silently in the background.";
      }

      // TOOLS: Define what AI can do
      final tools = [
        if (learnFromData)
          {
            'type': 'function',
            'function': {
              'name': 'note_health_insight',
              'description': 'Silently save a short, factual personalized insight (a symptom, health '
                  'concern, or preference the user mentioned) so it can be shown in their profile '
                  'later. Do not tell the user you called this.',
              'parameters': {
                'type': 'object',
                'properties': {
                  'category': {
                    'type': 'string',
                    'enum': ['symptom', 'concern', 'preference', 'note'],
                    'description': 'What kind of insight this is.',
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
        {
          'type': 'function',
          'function': {
            'name': 'add_reminder',
            'description': 'Add a recurring medicine reminder/alarm for the user. Only call this once you have a real, specific time — never a guessed one.',
            'parameters': {
              'type': 'object',
              'properties': {
                'title': {'type': 'string', 'description': 'The name of the medicine'},
                'dose': {'type': 'string', 'description': 'The dose amount (e.g. 500mg)'},
                'time': {'type': 'string', 'description': 'The exact clock time in "H:MM AM/PM" format, e.g. "9:00 AM" or "10:30 PM". Always include minutes, even if :00.'},
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
      ];

      final result = await GroqService.chatWithTools(
        systemPrompt: systemPrompt,
        history: chatHistory,
        tools: tools,
      );

      // Handle Automation (Tool Calls)
      if (result.hasToolCalls && reminderEngine != null) {
        final addedReminders = <Reminder>[];
        String? clarifyQuestion;
        List<String>? clarifyOptions;

        for (final tc in result.toolCalls!) {
          if (tc.name == 'note_health_insight') {
            final args = tc.arguments;
            final text = args['text']?.toString().trim() ?? '';
            if (text.isNotEmpty) {
              final category = AiInsightType.values.firstWhere(
                    (e) => e.name == args['category']?.toString(),
                orElse: () => AiInsightType.note,
              );
              await AiInsightsFirestoreService.instance.addInsight(AiInsight(
                type: category,
                text: text,
                createdAt: DateTime.now(),
                conversationId: currentConversationId,
              ));
            }
          } else if (tc.name == 'add_reminder') {
            final args = tc.arguments;
            final r = Reminder(
              title: args['title'] ?? 'Medicine',
              dose: args['dose'] ?? '',
              time: _normalizeTimeString(args['time']?.toString()),
              schedule: args['schedule'] ?? 'Daily',
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

        String responseText = result.content ?? '';
        if (addedReminders.isNotEmpty && responseText.isEmpty) {
          responseText = addedReminders.length == 1
              ? '${addedReminders.first.title} reminder set for ${addedReminders.first.time}.'
              : 'Set ${addedReminders.length} reminders.';
        }
        // If the ONLY thing the model did was the silent note_health_insight
        // call, it may not have also produced normal text in the same turn
        // — don't leave the user staring at a blank bubble.
        if (responseText.isEmpty && addedReminders.isEmpty && clarifyQuestion == null) {
          responseText = "Got it, thanks for sharing that.";
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
        await _reply(ChatMessage(role: ChatRole.ai, text: result.content ?? '', personalized: learnFromData));
      }

    } catch (e) {
      typing = false;
      debugPrint('[ChatProvider] Groq Error: $e');
      String errorMsg = "I'm having trouble responding. Please check your internet.";
      if (e.toString().contains('429')) {
        errorMsg = "Too many messages too fast — please wait a moment.";
      }
      await _reply(ChatMessage(role: ChatRole.ai, text: errorMsg));
    }
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

  void startRecording() { recording = true; notifyListeners(); }

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
}