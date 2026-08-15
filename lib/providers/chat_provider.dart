import 'dart:async';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../core/services/groq_service.dart';
import '../core/services/image_cleaner_service.dart';
import '../core/services/gemini_service.dart';
import '../core/services/ml_kit_ocr_service.dart';
import '../core/services/prescription_parser.dart';
import '../data/models/models.dart';
import '../services/chat_firestore_service.dart';
import 'profile_provider.dart';
import 'reminder_provider.dart';
import 'dart:convert';
import 'package:image/image.dart' as img;

/// MedAI — the in-app health assistant.
class ChatProvider extends ChangeNotifier {
  ChatProvider({this.reminderEngine, this.profileProvider}) {
    _initForCurrentUser();

    FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user?.uid == _initializedForUid) return;
      debugPrint('[ChatProvider] authStateChanged: ${user?.email}');
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

  Timer? _timer;
  String? currentConversationId;
  List<ChatConversationSummary> conversations = [];
  bool loadingConversations = false;

  // ---------------------------------------------------------------------
  // Startup / user switching
  // ---------------------------------------------------------------------

  Future<void> _initForCurrentUser() async {
    if (_initializing) return;
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

  Future<void> loadConversations() async {
    loadingConversations = true;
    notifyListeners();
    conversations = await ChatFirestoreService.instance.fetchConversations();
    loadingConversations = false;
    notifyListeners();
  }

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
          ? "Hi $name, I'm MedAI. I can answer health questions, read lab reports, and even scan prescriptions. Personal insights are on.\n\nHow are you feeling today?"
          : "Hi $name, I'm MedAI. I can answer health questions and read reports. Turn on Personal insights for tailored advice.\n\nHow are you feeling today?",
      personalized: learnFromData,
    );
    messages.add(greeting);
    notifyListeners();
    await _persist(greeting);
    await loadConversations();
  }

  Future<void> openConversation(String conversationId) async {
    currentConversationId = conversationId;
    messages.clear();
    pendingAttachments.clear();
    typing = false;
    notifyListeners();

    final history = await ChatFirestoreService.instance.fetchMessages(conversationId);
    messages.addAll(history);
    notifyListeners();
  }

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

  Future<void> stopRecording({required int seconds, bool cancelled = false, String? filePath}) async {
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
      await _reply(const ChatMessage(role: ChatRole.ai, text: "Access error."));
      return;
    }

    transcribing = true;
    notifyListeners();
    try {
      final transcript = await GroqService.transcribeAudio(filePath);
      transcribing = false;
      notifyListeners();
      if (transcript.trim().isNotEmpty) {
        await _routeReply(transcript.trim(), const []);
      }
    } catch (e) {
      transcribing = false;
      notifyListeners();
      await _reply(const ChatMessage(role: ChatRole.ai, text: "Transcription failed."));
    }
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

  Future<void> _replyFromPrescriptionScan(ChatAttachment photo) async {
    typing = true;
    notifyListeners();

    final path = photo.filePath;
    if (path == null) {
      typing = false;
      await _reply(const ChatMessage(role: ChatRole.ai, text: "Photo missing."));
      return;
    }

    try {
      // 1. Pre-process
      final finalPath = await ImageCleanerService.cleanForVision(path) ?? path;

      // 2. Primary: Gemini Developer API
      String cleaned;
      try {
        final jsonResponse = await GeminiService.readPrescription(finalPath);
        final data = jsonDecode(jsonResponse);
        cleaned = data['transcription'] as String? ?? '';
        if (cleaned.length < 5) throw Exception('Gemini output too short');
      } catch (e) {
        debugPrint('[ChatProvider] Gemini failed, falling back to ML Kit: $e');
        // 3. Fallback: ML Kit (Offline backup)
        cleaned = await MLKitOCRService.extractText(finalPath);
      }

      typing = false;
      if (cleaned.isEmpty) {
        await _reply(const ChatMessage(role: ChatRole.ai, text: "Could not read text."));
        return;
      }

      await _reply(ChatMessage(
        role: ChatRole.ai,
        card: ChatCardType.prescription,
        text: "I've analyzed the prescription. Please review the extracted medication details.",
        ocrText: cleaned,
      ));
    } catch (e) {
      typing = false;
      await _reply(const ChatMessage(role: ChatRole.ai, text: "OCR Error."));
    }
  }

  Future<void> noteRemindersAdded(int count) async {
    if (count <= 0) return;
    await _reply(ChatMessage(
      role: ChatRole.ai,
      text: 'Added $count reminder(s) successfully.',
    ));
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
    final id = currentConversationId;
    if (id != null) {
      await ChatFirestoreService.instance.saveMessage(id, message);
    }
  }

  Future<void> _replyDelayed(ChatMessage message) async {
    typing = true;
    notifyListeners();
    await Future.delayed(const Duration(milliseconds: 1000));
    await _reply(message);
  }

  Future<void> _replyFromGroq() async {
    typing = true;
    notifyListeners();
    try {
      final result = await GroqService.chatWithTools(
        systemPrompt: "You are MedAI, a friendly health assistant.",
        history: messages.where((m) => m.text.isNotEmpty).map((m) => {
          'role': m.role == ChatRole.user ? 'user' : 'assistant',
          'content': m.text,
        }).toList(),
        tools: [],
      );
      final content = result.content?.trim();
      if (content != null && content.isNotEmpty) {
        await _reply(ChatMessage(role: ChatRole.ai, text: content, personalized: learnFromData));
      }
    } catch (e) {
      typing = false;
      await _reply(const ChatMessage(role: ChatRole.ai, text: "Server error."));
    }
  }

  ChatMessage? _scriptedReply(String text, List<ChatAttachment> attachments) {
    // Basic red-flag escalation can go here
    return null;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
