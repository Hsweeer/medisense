import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../data/models/models.dart';

/// Handles all Firestore operations for MedAI chat history.
///
/// Schema (per user, so every user's chats are fully separate):
///   users/{uid}/medai_conversations/{conversationId}
///     - title, createdAtMs, updatedAtMs, lastMessagePreview
///   users/{uid}/medai_conversations/{conversationId}/messages/{messageId}
///     - the ChatMessage fields
///
/// This is the multi-thread model — each conversation is its own saved
/// chat the user can reopen later, the same way ChatGPT/Claude's history
/// works, rather than one single endless thread.
class ChatFirestoreService {
  ChatFirestoreService._();

  static final ChatFirestoreService instance = ChatFirestoreService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String? get _uid => _auth.currentUser?.uid;

  CollectionReference<Map<String, dynamic>>? _conversationsRef() {
    final uid = _uid;
    if (uid == null) return null;
    return _firestore.collection('users').doc(uid).collection('medai_conversations');
  }

  /// Lists all conversations for the logged-in user, most recently active
  /// first — this is what the chat-history screen shows.
  Future<List<ChatConversationSummary>> fetchConversations() async {
    final ref = _conversationsRef();
    if (ref == null) {
      debugPrint('[ChatFirestoreService] fetchConversations: user not logged in');
      return [];
    }
    try {
      final snapshot = await ref.orderBy('updatedAtMs', descending: true).get();
      final list = snapshot.docs
          .map((doc) => ChatConversationSummary.fromMap(doc.data(), doc.id))
          .toList();
      debugPrint('[ChatFirestoreService] fetchConversations: ${list.length} found');
      return list;
    } catch (e) {
      debugPrint('[ChatFirestoreService] fetchConversations: error — $e');
      return [];
    }
  }

  /// Creates a new, empty conversation and returns its ID.
  Future<String?> createConversation() async {
    final ref = _conversationsRef();
    if (ref == null) {
      debugPrint('[ChatFirestoreService] createConversation: user not logged in');
      return null;
    }
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final doc = await ref.add({
        'title': 'New chat',
        'createdAtMs': now,
        'updatedAtMs': now,
        'lastMessagePreview': '',
      });
      debugPrint('[ChatFirestoreService] createConversation: ${doc.id}');
      return doc.id;
    } catch (e) {
      debugPrint('[ChatFirestoreService] createConversation: error — $e');
      return null;
    }
  }

  /// Fetch the most recent [limit] messages in one conversation, oldest
  /// first (ready to render directly in the chat list).
  Future<List<ChatMessage>> fetchMessages(String conversationId,
      {int limit = 200}) async {
    final ref = _conversationsRef();
    if (ref == null) return [];
    try {
      final snapshot = await ref
          .doc(conversationId)
          .collection('messages')
          .orderBy('timestampMs', descending: true)
          .limit(limit)
          .get();

      final messages = snapshot.docs
          .map((doc) => ChatMessage.fromMap(doc.data(), doc.id))
          .toList()
          .reversed
          .toList();

      debugPrint(
          '[ChatFirestoreService] fetchMessages($conversationId): ${messages.length}');
      return messages;
    } catch (e) {
      debugPrint('[ChatFirestoreService] fetchMessages: error — $e');
      return [];
    }
  }

  /// Saves one message inside a conversation, waits for the write to
  /// actually complete (so it survives the app being killed right after),
  /// and updates the parent conversation's preview/title/updatedAt.
  /// Returns the message with its assigned Firestore ID, or the original
  /// message unchanged if the save fails (chat still works locally for
  /// that session either way).
  Future<ChatMessage> saveMessage(
      String conversationId, ChatMessage message) async {
    final ref = _conversationsRef();
    if (ref == null) {
      debugPrint('[ChatFirestoreService] saveMessage: user not logged in');
      return message;
    }

    try {
      final conversationDoc = ref.doc(conversationId);
      final docRef =
          await conversationDoc.collection('messages').add(message.toMap());

      final preview = message.text.trim().isNotEmpty
          ? message.text.trim()
          : (message.attachments.isNotEmpty
              ? message.attachments.first.name
              : '');
      final updates = <String, dynamic>{
        'updatedAtMs': DateTime.now().millisecondsSinceEpoch,
        if (preview.isNotEmpty) 'lastMessagePreview': preview,
      };
      // Auto-title the conversation from the user's first real message,
      // same pattern ChatGPT/Claude use — only overwrite the placeholder.
      if (message.role == ChatRole.user && message.text.trim().isNotEmpty) {
        final snap = await conversationDoc.get();
        final currentTitle = (snap.data()?['title'] as String?) ?? 'New chat';
        if (currentTitle == 'New chat') {
          final trimmed = message.text.trim();
          updates['title'] =
              trimmed.length > 48 ? '${trimmed.substring(0, 48)}…' : trimmed;
        }
      }
      await conversationDoc.update(updates);

      return ChatMessage(
        id: docRef.id,
        role: message.role,
        text: message.text,
        card: message.card,
        attachments: message.attachments,
        personalized: message.personalized,
        ocrText: message.ocrText,
        timestamp: message.timestamp ?? DateTime.now(),
      );
    } catch (e) {
      debugPrint('[ChatFirestoreService] saveMessage: error — $e');
      return message;
    }
  }

  /// Deletes a whole conversation (all its messages, then the conversation
  /// doc itself). Firestore batched writes cap at 500 ops, so this deletes
  /// messages in pages.
  Future<void> deleteConversation(String conversationId) async {
    final ref = _conversationsRef();
    if (ref == null) return;
    try {
      final messagesRef = ref.doc(conversationId).collection('messages');
      while (true) {
        final snapshot = await messagesRef.limit(300).get();
        if (snapshot.docs.isEmpty) break;
        final batch = _firestore.batch();
        for (final doc in snapshot.docs) {
          batch.delete(doc.reference);
        }
        await batch.commit();
      }
      await ref.doc(conversationId).delete();
      debugPrint('[ChatFirestoreService] deleteConversation: $conversationId done');
    } catch (e) {
      debugPrint('[ChatFirestoreService] deleteConversation: error — $e');
    }
  }
}