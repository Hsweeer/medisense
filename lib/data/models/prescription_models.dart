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

  /// Recent scans (last 30 days) appear under History → New.
  /// Older scans appear under History → Old.
  static const recentWindow = Duration(days: 30);

  bool get isNew {
    final age = DateTime.now().difference(scannedAt);
    return age <= recentWindow;
  }

  /// First non-empty lines of the summary for list previews.
  String get preview {
    final lines = summary
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    if (lines.isEmpty) return 'Prescription scan';
    // Skip the title line if present; show the next useful line.
    final start = lines.first.toUpperCase().startsWith('PRESCRIPTION')
        ? (lines.length > 1 ? 1 : 0)
        : 0;
    final chunk = lines.skip(start).take(2).join(' · ');
    if (chunk.length <= 90) return chunk;
    return '${chunk.substring(0, 87)}…';
  }

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