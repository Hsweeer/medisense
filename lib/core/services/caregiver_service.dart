import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../data/models/caregiver_models.dart';
import '../../data/models/models.dart';
import '../../services/notification_server_client.dart';

class CaregiverService {
  CaregiverService._();
  static final instance = CaregiverService._();

  final _db = FirebaseFirestore.instance;
  String get _uid => FirebaseAuth.instance.currentUser!.uid;

  CollectionReference<Map<String, dynamic>> get _users =>
      _db.collection('users');
  CollectionReference<Map<String, dynamic>> get _links =>
      _db.collection('caregiver_links');

  Future<List<AppUserSummary>> searchUsers(String query) async {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return [];

    final snapshot = await _users
        .where('searchIndex', arrayContains: normalized)
        .limit(15)
        .get();

    return snapshot.docs
        .where((d) => d.id != _uid)
        .map((d) => AppUserSummary.fromMap(d.data(), d.id))
        .toList();
  }

  Future<AppUserSummary?> findByPhone(String phone) async {
    final normalized = phone.replaceAll(RegExp(r'[^\d+]'), '');
    final snapshot = await _users
        .where('phone', isEqualTo: normalized)
        .limit(1)
        .get();
    if (snapshot.docs.isEmpty) return null;
    final doc = snapshot.docs.first;
    return AppUserSummary.fromMap(doc.data(), doc.id);
  }

  Future<void> sendRequest(AppUserSummary recipient) async {
    final me = await _users.doc(_uid).get();
    final myName = me.data()?['name'] ?? 'Someone';

    final id = CaregiverLink.idFor(_uid, recipient.uid);
    await _links
        .doc(id)
        .set(
          CaregiverLink(
            id: id,
            senderUid: _uid,
            senderName: myName,
            recipientUid: recipient.uid,
            recipientName: recipient.name,
            status: CaregiverLinkStatus.pending,
            requestedAt: DateTime.now(),
          ).toMap(),
        );

    try {
      await NotificationServerClient.notifyCaregiverRequest(id);
    } catch (_) {
      // Best-effort: the Firestore write is still successful even if the push
      // server is temporarily unavailable.
    }
  }

  Future<void> respondToRequest(String linkId, {required bool accept}) async {
    await NotificationServerClient.respondCaregiverRequest(
      requestId: linkId,
      action: accept ? 'accept' : 'reject',
    );
  }

  Stream<List<CaregiverLink>> incomingRequests() {
    return _links
        .where('recipientUid', isEqualTo: _uid)
        .where('status', isEqualTo: CaregiverLinkStatus.pending.name)
        .snapshots()
        .map(
          (s) =>
              s.docs.map((d) => CaregiverLink.fromMap(d.data(), d.id)).toList(),
        );
  }

  /// Every request I've ever sent, in every status (pending, accepted,
  /// declined, restricted). Unlike [myAcceptedRecipients] (accepted only),
  /// this exists so a watcher can detect the pending → accepted/declined
  /// transition and notify me when someone responds to my request.
  Stream<List<CaregiverLink>> mySentRequests() {
    return _links
        .where('senderUid', isEqualTo: _uid)
        .snapshots()
        .map(
          (s) =>
              s.docs.map((d) => CaregiverLink.fromMap(d.data(), d.id)).toList(),
        );
  }

  Stream<List<CaregiverLink>> myAcceptedRecipients() {
    return _links
        .where('senderUid', isEqualTo: _uid)
        .where('status', isEqualTo: CaregiverLinkStatus.accepted.name)
        .snapshots()
        .map(
          (s) =>
              s.docs.map((d) => CaregiverLink.fromMap(d.data(), d.id)).toList(),
        );
  }

  Stream<List<CaregiverLink>> whoHasAccessToMe() {
    return _links
        .where('recipientUid', isEqualTo: _uid)
        .where('status', isEqualTo: CaregiverLinkStatus.accepted.name)
        .snapshots()
        .map(
          (s) =>
              s.docs.map((d) => CaregiverLink.fromMap(d.data(), d.id)).toList(),
        );
  }

  Future<void> revokeAccess(String linkId) async {
    await _links.doc(linkId).update({
      'status': CaregiverLinkStatus.restricted.name,
      'respondedAtMs': DateTime.now().millisecondsSinceEpoch,
    });

    try {
      await NotificationServerClient.notifyCaregiverResponse(linkId);
    } catch (_) {
      // Best-effort notification after a status change outside the accept/reject flow.
    }
  }

  Future<void> cancelRemindersFrom(String senderUid) async {
    final reminders = await _db
        .collection('users')
        .doc(_uid)
        .collection('reminders')
        .where('createdByUid', isEqualTo: senderUid)
        .get();

    final batch = _db.batch();
    for (final doc in reminders.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }

  Future<void> _assertAccepted(String recipientUid) async {
    final id = CaregiverLink.idFor(_uid, recipientUid);
    final doc = await _links.doc(id).get();
    final status = doc.data()?['status'];
    if (status != CaregiverLinkStatus.accepted.name) {
      throw StateError('No accepted caregiver permission for this recipient.');
    }
  }

  Future<void> createReminderForRecipients({
    required Reminder reminder,
    required List<String> recipientUids,
  }) async {
    for (final recipientUid in recipientUids) {
      await _assertAccepted(recipientUid);

      final data = reminder.toMap()
        ..['createdByUid'] = _uid
        ..['recipientUid'] = recipientUid;

      final reminderDoc = await _db
          .collection('users')
          .doc(recipientUid)
          .collection('reminders')
          .add(data);

      if (_uid != recipientUid) {
        try {
          await NotificationServerClient.notifyReminder(
            recipientUid: recipientUid,
            reminderId: reminderDoc.id,
          );
        } catch (_) {
          // Best-effort: Firestore reminder creation still succeeds if the push
          // server is unavailable.
        }
      }
    }
  }

  Future<void> updateReminderForRecipient({
    required String recipientUid,
    required String reminderDocId,
    required Map<String, dynamic> changes,
  }) async {
    await _db
        .collection('users')
        .doc(recipientUid)
        .collection('reminders')
        .doc(reminderDocId)
        .update(changes);
  }

  Future<void> deleteReminderForRecipient({
    required String recipientUid,
    required String reminderDocId,
  }) async {
    await _db
        .collection('users')
        .doc(recipientUid)
        .collection('reminders')
        .doc(reminderDocId)
        .delete();
  }
}

/*
FIRESTORE SECURITY RULES — add to firestore.rules:

match /users/{recipientUid}/reminders/{reminderId} {
  allow read: if request.auth.uid == recipientUid;

  allow create: if request.auth.uid == recipientUid
    || (
      request.resource.data.createdByUid == request.auth.uid
      && exists(/databases/$(database)/documents/caregiver_links/$(request.auth.uid + '_' + recipientUid))
      && get(/databases/$(database)/documents/caregiver_links/$(request.auth.uid + '_' + recipientUid)).data.status == 'accepted'
    );

  allow update, delete: if request.auth.uid == recipientUid
    || request.auth.uid == resource.data.createdByUid;
}

match /caregiver_links/{linkId} {
  allow read: if request.auth.uid == resource.data.senderUid
    || request.auth.uid == resource.data.recipientUid;

  allow create: if request.auth.uid == request.resource.data.senderUid;

  allow update: if request.auth.uid == resource.data.recipientUid;
}
*/
