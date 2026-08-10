import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../data/models/models.dart';

/// Handles all Firestore operations for MedAI chat history.
/// Messages are stored at: users/{uid}/medai_chat/{messageId}
class ChatFirestoreService {
  ChatFirestoreService._();

  static final ChatFirestoreService instance = ChatFirestoreService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String? get _uid => _auth.currentUser?.uid;

  bool get isLoggedIn => _uid != null;

  /// Fetch the most recent [limit] messages for the logged-in user, oldest
  /// first (ready to render directly in a chat list).
  Future<List<ChatMessage>> fetchRecentMessages({int limit = 60}) async {
    final uid = _uid;
    if (uid == null) {
      debugPrint('[ChatFirestoreService] fetchRecentMessages: user not logged in');
      return [];
    }

    try {
      final snapshot = await _firestore
          .collection('users')
          .doc(uid)
          .collection('medai_chat')
          .orderBy('timestampMs', descending: true)
          .limit(limit)
          .get();

      final messages = snapshot.docs
          .map((doc) => ChatMessage.fromMap(doc.data(), doc.id))
          .toList()
          .reversed // we fetched newest-first, flip back to oldest-first
          .toList();

      debugPrint(
          '[ChatFirestoreService] fetchRecentMessages: loaded ${messages.length} messages');
      return messages;
    } catch (e) {
      debugPrint('[ChatFirestoreService] fetchRecentMessages: error — $e');
      return [];
    }
  }

  /// Saves one message and returns it with its assigned Firestore ID.
  /// Returns the original message unchanged (with a null id) on failure —
  /// the chat still works locally for that session even if the save fails.
  Future<ChatMessage> saveMessage(ChatMessage message) async {
    final uid = _uid;
    if (uid == null) {
      debugPrint('[ChatFirestoreService] saveMessage: user not logged in');
      return message;
    }

    try {
      final docRef = await _firestore
          .collection('users')
          .doc(uid)
          .collection('medai_chat')
          .add(message.toMap());

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

  /// Wipes the whole chat history for the logged-in user (used by "Clear
  /// chat" / starting fresh). Deletes in small batches — Firestore batched
  /// writes cap at 500 operations.
  Future<void> clearHistory() async {
    final uid = _uid;
    if (uid == null) return;

    try {
      final collection =
          _firestore.collection('users').doc(uid).collection('medai_chat');
      while (true) {
        final snapshot = await collection.limit(300).get();
        if (snapshot.docs.isEmpty) break;
        final batch = _firestore.batch();
        for (final doc in snapshot.docs) {
          batch.delete(doc.reference);
        }
        await batch.commit();
      }
      debugPrint('[ChatFirestoreService] clearHistory: done');
    } catch (e) {
      debugPrint('[ChatFirestoreService] clearHistory: error — $e');
    }
  }
}