/// A single notification history entry, persisted locally as JSON.
///
/// This is intentionally a plain, dependency-free model (no Firestore
/// helpers) since notification history lives only on-device.
class NotificationItem {
  NotificationItem({
    required this.id,
    required this.title,
    required this.message,
    required this.date,
    required this.time,
    required this.createdAt,
    this.isRead = false,
  });

  final String id;
  final String title;
  final String message;

  /// Display date, e.g. "30 Jul 2026".
  final String date;

  /// Display time, e.g. "9:00 AM".
  final String time;

  /// Real timestamp used for sorting (newest first) and for building
  /// [date]/[time] when a notification is first created.
  final DateTime createdAt;

  bool isRead;

  factory NotificationItem.fromMap(Map<String, dynamic> map) {
    return NotificationItem(
      id: (map['id'] ?? '').toString(),
      title: map['title'] as String? ?? '',
      message: map['message'] as String? ?? '',
      date: map['date'] as String? ?? '',
      time: map['time'] as String? ?? '',
      createdAt:
      DateTime.tryParse(map['createdAt'] as String? ?? '') ??
          DateTime.now(),
      isRead: map['isRead'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'title': title,
    'message': message,
    'date': date,
    'time': time,
    'createdAt': createdAt.toIso8601String(),
    'isRead': isRead,
  };

  NotificationItem copyWith({bool? isRead}) => NotificationItem(
    id: id,
    title: title,
    message: message,
    date: date,
    time: time,
    createdAt: createdAt,
    isRead: isRead ?? this.isRead,
  );
}