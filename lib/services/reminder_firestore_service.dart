import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../data/models/models.dart';

/// Handles all Firestore operations for reminders.
/// Reminders are stored at: users/{uid}/reminders/{reminderId}
class ReminderFirestoreService {
  ReminderFirestoreService._();

  static final ReminderFirestoreService instance = ReminderFirestoreService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String? get _uid => _auth.currentUser?.uid;

  bool get isLoggedIn => _uid != null;

  /// Fetch all reminders for the logged-in user.
  Future<List<Reminder>> fetchReminders() async {
    final uid = _uid;
    if (uid == null) {
      debugPrint('[ReminderFirestoreService] fetchReminders: user not logged in');
      return [];
    }

    try {
      final snapshot = await _firestore
          .collection('users')
          .doc(uid)
          .collection('reminders')
          .orderBy('createdAt', descending: true)
          .get();

      final reminders = snapshot.docs
          .map((doc) => Reminder.fromMap(doc.data(), doc.id))
          .toList();

      debugPrint(
          '[ReminderFirestoreService] fetchReminders: loaded ${reminders.length} reminders');
      return reminders;
    } catch (e) {
      debugPrint('[ReminderFirestoreService] fetchReminders: error — $e');
      return [];
    }
  }

  /// Create a new reminder and return it with the assigned Firestore ID.
  Future<Reminder?> createReminder(Reminder reminder) async {
    final uid = _uid;
    if (uid == null) {
      debugPrint('[ReminderFirestoreService] createReminder: user not logged in');
      return null;
    }

    try {
      final docRef = await _firestore
          .collection('users')
          .doc(uid)
          .collection('reminders')
          .add(reminder.toMap());

      reminder.id = docRef.id;
      debugPrint(
          '[ReminderFirestoreService] createReminder: saved id=${reminder.id} title=${reminder.title}');
      return reminder;
    } catch (e) {
      debugPrint('[ReminderFirestoreService] createReminder: error — $e');
      return null;
    }
  }

  /// Update an existing reminder (requires reminder.id to be set).
  Future<bool> updateReminder(Reminder reminder) async {
    final uid = _uid;
    if (uid == null || reminder.id == null) {
      debugPrint(
          '[ReminderFirestoreService] updateReminder: user not logged in or id is null');
      return false;
    }

    try {
      await _firestore
          .collection('users')
          .doc(uid)
          .collection('reminders')
          .doc(reminder.id)
          .update(reminder.toMap());

      debugPrint(
          '[ReminderFirestoreService] updateReminder: updated id=${reminder.id} title=${reminder.title}');
      return true;
    } catch (e) {
      debugPrint('[ReminderFirestoreService] updateReminder: error — $e');
      return false;
    }
  }

  /// Delete a reminder by ID.
  Future<bool> deleteReminder(String reminderId) async {
    final uid = _uid;
    if (uid == null) {
      debugPrint('[ReminderFirestoreService] deleteReminder: user not logged in');
      return false;
    }

    try {
      await _firestore
          .collection('users')
          .doc(uid)
          .collection('reminders')
          .doc(reminderId)
          .delete();

      debugPrint('[ReminderFirestoreService] deleteReminder: deleted id=$reminderId');
      return true;
    } catch (e) {
      debugPrint('[ReminderFirestoreService] deleteReminder: error — $e');
      return false;
    }
  }

  /// Listen to real-time updates for reminders.
  Stream<List<Reminder>> remindersStream() {
    final uid = _uid;
    if (uid == null) {
      return Stream.value([]);
    }

    return _firestore
        .collection('users')
        .doc(uid)
        .collection('reminders')
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => Reminder.fromMap(doc.data(), doc.id))
            .toList());
  }
}
