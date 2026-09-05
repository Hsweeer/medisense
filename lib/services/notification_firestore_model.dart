// Intentionally left minimal — NotificationRepository maps Firestore docs
// into NotificationItem (local model) so a separate model file is optional.
// This placeholder exists to make future expansions easier.

class NotificationFirestoreModel {
  final String id;
  final Map<String, dynamic> data;

  NotificationFirestoreModel({required this.id, required this.data});
}
