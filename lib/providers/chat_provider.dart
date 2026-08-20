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
import '../services/chat_firestore_service.dart';
import '../services/skin_scan_firestore_service.dart';
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

      String systemPrompt = "You are MedAI, a helpful health assistant.";

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

      // TOOLS: Define what AI can do
      final tools = [
        {
          'type': 'function',
          'function': {
            'name': 'add_reminder',
            'description': 'Add a recurring medicine reminder/alarm for the user.',
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
        }
      ];

      final result = await GroqService.chatWithTools(
        systemPrompt: systemPrompt,
        history: chatHistory,
        tools: tools,
      );

      // Handle Automation (Tool Calls)
      if (result.hasToolCalls && reminderEngine != null) {
        bool added = false;
        for (final tc in result.toolCalls!) {
          if (tc.name == 'add_reminder') {
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
            added = true;
          }
        }

        String responseText = result.content ?? '';
        if (added && responseText.isEmpty) {
          responseText = 'Reminder set successfully.';
        }
        await _reply(ChatMessage(role: ChatRole.ai, text: responseText, personalized: learnFromData));
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