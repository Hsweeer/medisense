/// One saved prescription scan — the professional summary MedAI generated,
/// kept in the user's history the same way a scanned meal is kept in their
/// nutrition history (see [FoodLogEntry]).
class PrescriptionHistoryEntry {
  const PrescriptionHistoryEntry({
    this.id,
    required this.summary,
    required this.medicineCount,
    required this.scannedAt,
    this.photoUrl,
  });

  final String? id;

  /// The full professional Rx-style summary text (same text shown in chat
  /// and on the review screen).
  final String summary;

  final int medicineCount;
  final DateTime scannedAt;
  final String? photoUrl;

  Map<String, dynamic> toMap() => {
    'summary': summary,
    'medicineCount': medicineCount,
    'scannedAtMs': scannedAt.millisecondsSinceEpoch,
    'photoUrl': photoUrl,
  };

  factory PrescriptionHistoryEntry.fromMap(
      Map<String, dynamic> map, String id) =>
      PrescriptionHistoryEntry(
        id: id,
        summary: map['summary'] ?? '',
        medicineCount: (map['medicineCount'] as num?)?.toInt() ?? 0,
        scannedAt: map['scannedAtMs'] != null
            ? DateTime.fromMillisecondsSinceEpoch(map['scannedAtMs'])
            : DateTime.now(),
        photoUrl: map['photoUrl'],
      );
}