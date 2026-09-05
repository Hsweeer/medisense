import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../data/models/notification_model.dart';

class NotificationRepository {
  NotificationRepository._();
  static final instance = NotificationRepository._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _notificationsRefFor(String uid) =>
      _db.collection('users').doc(uid).collection('notifications');

  Future<String?> createNotification({
    required String recipientUid,
    required String senderUid,
    required String type,
    required String title,
    required String body,
    Map<String, dynamic>? meta,
    String? relatedEntityId,
    String? relatedEntityType,
    Map<String, dynamic>? route,
  }) async {
    try {
      final docRef = await _notificationsRefFor(recipientUid).add({
        'recipientUserId': recipientUid,
        'senderUserId': senderUid,
        'type': type,
        'title': title,
        'body': body,
        'meta': meta ?? {},
        'relatedEntityId': relatedEntityId ?? null,
        'relatedEntityType': relatedEntityType ?? null,
        'route': route ?? {},
        'createdAt': FieldValue.serverTimestamp(),
        'isRead': false,
        'status': 'pending',
      });
      return docRef.id;
    } catch (e) {
      debugPrint('[NotificationRepository] createNotification error: $e');
      return null;
    }
  }

  Stream<List<NotificationItem>> notificationsStream(String uid) {
    return _notificationsRefFor(uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((d) {
              final data = d.data();
              final ts = data['createdAt'];
              DateTime createdAt;
              if (ts == null) {
                createdAt = DateTime.now();
              } else if (ts is Timestamp) {
                createdAt = ts.toDate();
              } else if (ts is DateTime) {
                createdAt = ts;
              } else {
                createdAt = DateTime.now();
              }

              final date = '${createdAt.day.toString().padLeft(2, '0')}-${createdAt.month.toString().padLeft(2, '0')}-${createdAt.year}';
              final time = '${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')}';

              return NotificationItem(
                id: d.id,
                title: data['title'] as String? ?? '',
                message: data['body'] as String? ?? '',
                date: date,
                time: time,
                createdAt: createdAt,
                isRead: data['isRead'] as bool? ?? false,
              );
            }).toList());
  }

  Future<void> markAsRead(String uid, String notificationId) async {
    try {
      await _notificationsRefFor(uid).doc(notificationId).update({'isRead': true, 'readAt': FieldValue.serverTimestamp()});
    } catch (e) {
      debugPrint('[NotificationRepository] markAsRead error: $e');
    }
  }

  Future<void> delete(String uid, String notificationId) async {
    try {
      await _notificationsRefFor(uid).doc(notificationId).delete();
    } catch (e) {
      debugPrint('[NotificationRepository] delete error: $e');
    }
  }

  /// Calls the backend Cloud Function to accept/reject a caregiver request.
  /// action must be 'accept' or 'reject'. Returns the Cloud Function response map.
  Future<Map<String, dynamic>?> respondCaregiverRequest({
    required String action,
    required String requestId,
  }) async {
    try {
      final callable = FirebaseFunctions.instance.httpsCallable('respondCaregiverRequest');
      final res = await callable.call({'action': action, 'requestId': requestId});
      if (res.data is Map) return Map<String, dynamic>.from(res.data as Map);
      return {'result': res.data};
    } catch (e) {
      debugPrint('[NotificationRepository] respondCaregiverRequest error: $e');
      return null;
    }
  }

  /// Update notification status field (e.g., 'actioned','cancelled')
  Future<void> updateNotificationStatus(String uid, String notificationId, String status) async {
    try {
      await _notificationsRefFor(uid).doc(notificationId).update({'status': status, 'statusUpdatedAt': FieldValue.serverTimestamp()});
    } catch (e) {
      debugPrint('[NotificationRepository] updateNotificationStatus error: $e');
    }
  }

  /// Fetch raw notification document data (includes meta/route) for deep-linking or action.
  Future<Map<String, dynamic>?> fetchNotificationDoc(String uid, String notificationId) async {
    try {
      final snap = await _notificationsRefFor(uid).doc(notificationId).get();
      if (!snap.exists) return null;
      return snap.data();
    } catch (e) {
      debugPrint('[NotificationRepository] fetchNotificationDoc error: $e');
      return null;
    }
  }
}

