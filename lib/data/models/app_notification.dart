/// Centralized notification model backing the whole app's notification
/// system (SOS, caregiver requests, reminders, and anything added later).
///
/// Persisted in Firestore at `users/{recipientUserId}/notifications/{id}`
/// (see NotificationRepository) and mirrored to the device via FCM. This
/// file intentionally has ONE model + ONE set of enums so every feature
/// (SOS, caregiver, reminders) reuses the same shape instead of inventing
/// its own — do not create a parallel notification model for a new
/// feature; add a new [AppNotificationType] value instead.
library;

/// What kind of event this notification represents. Add new values here
/// as new features need to notify a user — never create a separate
/// notification system for a new feature.
enum AppNotificationType {
  sosAlert,
  sosResolved,
  caregiverRequest,
  caregiverRequestAccepted,
  caregiverRequestRejected,
  caregiverRequestRevoked,
  // Reminders keep firing locally on-device (exact alarms) — these types
  // are only for the *cross-user* side: e.g. a caregiver created/edited/
  // cancelled a reminder for someone else, or a caregiver-visible patient
  // action on a reminder they created.
  reminderCreated,
  reminderUpdated,
  reminderCancelled,
  reminderCompleted,
  generic;

  static AppNotificationType fromName(String? name) {
    return AppNotificationType.values.firstWhere(
          (value) => value.name == name,
      orElse: () => AppNotificationType.generic,
    );
  }
}

/// What kind of entity [AppNotification.relatedEntityId] points to, so the
/// notification router knows which screen to open and which Firestore
/// document to re-validate before allowing an action.
enum AppNotificationEntityType {
  sosSession,
  caregiverLink,
  reminder,
  none;

  static AppNotificationEntityType fromName(String? name) {
    return AppNotificationEntityType.values.firstWhere(
          (value) => value.name == name,
      orElse: () => AppNotificationEntityType.none,
    );
  }
}

/// Lifecycle status of the notification itself (not the underlying entity).
/// `actioned` means the recipient tapped Accept/Reject/etc. from the
/// notification itself; the source of truth for whether that action was
/// actually valid always remains the related Firestore entity.
enum AppNotificationStatus {
  pending,
  sent,
  failed,
  actioned,
  cancelled,
  expired;

  static AppNotificationStatus fromName(String? name) {
    return AppNotificationStatus.values.firstWhere(
          (value) => value.name == name,
      orElse: () => AppNotificationStatus.sent,
    );
  }
}

class AppNotification {
  const AppNotification({
    required this.id,
    required this.recipientUserId,
    required this.senderUserId,
    required this.senderName,
    required this.type,
    required this.title,
    required this.body,
    required this.createdAt,
    this.isRead = false,
    this.status = AppNotificationStatus.sent,
    this.relatedEntityId,
    this.relatedEntityType = AppNotificationEntityType.none,
    this.data = const {},
  });

  final String id;
  final String recipientUserId;

  /// Empty string for system-generated notifications with no human sender
  /// (e.g. an expiry sweep).
  final String senderUserId;
  final String senderName;

  final AppNotificationType type;
  final String title;
  final String body;
  final DateTime createdAt;

  final bool isRead;
  final AppNotificationStatus status;

  /// The id of the entity this notification is about — a sosSessionId,
  /// caregiver_links doc id, or reminderId. Null for notifications with no
  /// specific destination (rare — every actionable notification should set
  /// this so the router can deep-link and re-validate state).
  final String? relatedEntityId;
  final AppNotificationEntityType relatedEntityType;

  /// Extra fields a specific type needs (e.g. a reminder's displayTime).
  /// Keep this small — structured fields above should be preferred.
  final Map<String, dynamic> data;

  factory AppNotification.fromMap(Map<String, dynamic> map, String id) {
    return AppNotification(
      id: id,
      recipientUserId: (map['recipientUserId'] as String?) ?? '',
      senderUserId: (map['senderUserId'] as String?) ?? '',
      senderName: (map['senderName'] as String?) ?? '',
      type: AppNotificationType.fromName(map['type'] as String?),
      title: (map['title'] as String?) ?? '',
      body: (map['body'] as String?) ?? '',
      createdAt: _dateFromMap(map['createdAt']),
      isRead: map['isRead'] as bool? ?? false,
      status: AppNotificationStatus.fromName(map['status'] as String?),
      relatedEntityId: map['relatedEntityId'] as String?,
      relatedEntityType: AppNotificationEntityType.fromName(
        map['relatedEntityType'] as String?,
      ),
      data: (map['data'] as Map?)?.cast<String, dynamic>() ?? const {},
    );
  }

  Map<String, dynamic> toMap() => {
    'recipientUserId': recipientUserId,
    'senderUserId': senderUserId,
    'senderName': senderName,
    'type': type.name,
    'title': title,
    'body': body,
    'createdAt': createdAt.millisecondsSinceEpoch,
    'isRead': isRead,
    'status': status.name,
    if (relatedEntityId != null) 'relatedEntityId': relatedEntityId,
    'relatedEntityType': relatedEntityType.name,
    if (data.isNotEmpty) 'data': data,
  };

  /// Flat key/value payload for an FCM data message. FCM payload values
  /// must all be strings.
  Map<String, String> toFcmData() => {
    'notificationId': id,
    'type': type.name,
    'relatedEntityType': relatedEntityType.name,
    if (relatedEntityId != null) 'relatedEntityId': relatedEntityId!,
    for (final entry in data.entries) entry.key: entry.value.toString(),
  };

  AppNotification copyWith({
    bool? isRead,
    AppNotificationStatus? status,
  }) => AppNotification(
    id: id,
    recipientUserId: recipientUserId,
    senderUserId: senderUserId,
    senderName: senderName,
    type: type,
    title: title,
    body: body,
    createdAt: createdAt,
    isRead: isRead ?? this.isRead,
    status: status ?? this.status,
    relatedEntityId: relatedEntityId,
    relatedEntityType: relatedEntityType,
    data: data,
  );

  static DateTime _dateFromMap(dynamic value) {
    if (value is DateTime) return value;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    return DateTime.now();
  }
}