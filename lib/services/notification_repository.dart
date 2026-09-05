import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../data/models/app_notification.dart';

/// Single Firestore-backed source of truth for notification records.
///
/// Every feature (SOS, caregiver requests, reminders, anything added
/// later) writes and reads notifications through this repository instead
/// of a feature-specific store. Structure:
///
///   users/{recipientUserId}/notifications/{notificationId}
///
/// This mirrors the existing `users/{uid}/reminders/{id}` subcollection
/// pattern already used in this project, and is covered by the existing
/// `match /{allSubcollections=**}` rule under `users/{userId}` (owner-only
/// read/write), so no new top-level security rule is required for it.
class NotificationRepository {
  NotificationRepository._();
  static final instance = NotificationRepository._();

  final _db = FirebaseFirestore.instance;
  String get _uid => FirebaseAuth.instance.currentUser!.uid;

  CollectionReference<Map<String, dynamic>> _notificationsFor(String uid) =>
      _db.collection('users').doc(uid).collection('notifications');

  /// Live stream of a user's notifications, newest first.
  Stream<List<AppNotification>> notificationsStream(
    String uid, {
    int limit = 100,
  }) {
    return _notificationsFor(uid)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((d) => AppNotification.fromMap(d.data(), d.id))
              .toList(),
        );
  }

  /// Live stream of the current user's notifications, newest first.
  Stream<List<AppNotification>> watchMine({int limit = 100}) {
    return notificationsStream(_uid, limit: limit);
  }

  /// Live unread count for badges.
  Stream<int> watchUnreadCount() {
    return _notificationsFor(
      _uid,
    ).where('isRead', isEqualTo: false).snapshots().map((s) => s.docs.length);
  }

  /// Fetch a single notification by id (any recipient — used right after
  /// a push arrives, where we already know the recipient is the current
  /// user because it was addressed to their token).
  Future<AppNotification?> getById(String notificationId) async {
    final doc = await _notificationsFor(_uid).doc(notificationId).get();
    if (!doc.exists) return null;
    return AppNotification.fromMap(doc.data()!, doc.id);
  }

  /// Creates a notification document for [recipientUserId]. Returns the
  /// created notification (with its generated id) so callers can pass it
  /// straight to an FCM-send Cloud Function call.
  Future<AppNotification> create({
    required String recipientUserId,
    required String senderUserId,
    required String senderName,
    required AppNotificationType type,
    required String title,
    required String body,
    String? relatedEntityId,
    AppNotificationEntityType relatedEntityType = AppNotificationEntityType.none,
    Map<String, dynamic> data = const {},
  }) async {
    final ref = _notificationsFor(recipientUserId).doc();
    final notification = AppNotification(
      id: ref.id,
      recipientUserId: recipientUserId,
      senderUserId: senderUserId,
      senderName: senderName,
      type: type,
      title: title,
      body: body,
      createdAt: DateTime.now(),
      status: AppNotificationStatus.pending,
      relatedEntityId: relatedEntityId,
      relatedEntityType: relatedEntityType,
      data: data,
    );
    await ref.set(notification.toMap());
    return notification;
  }

  Future<AppNotification> createNotification({
    required String recipientUid,
    required String senderUid,
    required dynamic type,
    required String title,
    required String body,
    String? relatedEntityId,
    dynamic relatedEntityType,
    Map<String, dynamic>? route,
  }) async {
    final resolvedType = type is AppNotificationType
        ? type
        : AppNotificationType.values.firstWhere(
            (value) => value.name == type,
            orElse: () => AppNotificationType.generic,
          );
    final resolvedEntityType = relatedEntityType is AppNotificationEntityType
        ? relatedEntityType
        : AppNotificationEntityType.values.firstWhere(
            (value) => value.name == relatedEntityType,
            orElse: () => AppNotificationEntityType.none,
          );

    return create(
      recipientUserId: recipientUid,
      senderUserId: senderUid,
      senderName: '',
      type: resolvedType,
      title: title,
      body: body,
      relatedEntityId: relatedEntityId,
      relatedEntityType: resolvedEntityType,
      data: route != null ? {'route': route} : const {},
    );
  }

  Future<void> markRead(String notificationId, {bool read = true}) {
    return _notificationsFor(
      _uid,
    ).doc(notificationId).update({'isRead': read});
  }

  Future<void> markAsRead(String uid, String notificationId, {bool read = true}) {
    return _notificationsFor(uid).doc(notificationId).update({'isRead': read});
  }

  Future<void> markAllRead() async {
    final unread = await _notificationsFor(
      _uid,
    ).where('isRead', isEqualTo: false).get();
    if (unread.docs.isEmpty) return;
    final batch = _db.batch();
    for (final doc in unread.docs) {
      batch.update(doc.reference, {'isRead': true});
    }
    await batch.commit();
  }

  /// Marks a notification as `actioned` (e.g. Accept/Reject was tapped
  /// from it) or `cancelled`/`expired` when the underlying entity moved
  /// on without this notification's action being used. Never treat this
  /// as authorization to perform the action — always re-check the related
  /// Firestore entity's current state first.
  Future<void> updateStatus(
      String notificationId,
      AppNotificationStatus status,
      ) {
    return _notificationsFor(
      _uid,
    ).doc(notificationId).update({'status': status.name});
  }

  Future<void> delete(String notificationId) {
    return _notificationsFor(_uid).doc(notificationId).delete();
  }

  Future<void> deleteNotification(String uid, String notificationId) {
    return _notificationsFor(uid).doc(notificationId).delete();
  }
}