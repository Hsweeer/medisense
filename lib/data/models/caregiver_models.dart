enum CaregiverLinkStatus { pending, accepted, declined, restricted }

class AppUserSummary {
  const AppUserSummary({
    required this.uid,
    required this.name,
    required this.phone,
    this.email = '',
  });

  final String uid;
  final String name;
  final String phone;
  final String email;

  factory AppUserSummary.fromMap(Map<String, dynamic> map, String uid) {
    return AppUserSummary(
      uid: uid,
      name: (map['name'] as String?)?.trim().isNotEmpty == true
          ? map['name'] as String
          : 'User',
      phone: (map['phone'] as String?) ?? '',
      email: (map['email'] as String?) ?? '',
    );
  }
}

class CaregiverLink {
  const CaregiverLink({
    required this.id,
    required this.senderUid,
    required this.senderName,
    required this.recipientUid,
    required this.recipientName,
    required this.status,
    required this.requestedAt,
    this.respondedAt,
  });

  final String id;
  final String senderUid;
  final String senderName;
  final String recipientUid;
  final String recipientName;
  final CaregiverLinkStatus status;
  final DateTime requestedAt;
  final DateTime? respondedAt;

  static String idFor(String senderUid, String recipientUid) =>
      '${senderUid}_$recipientUid';

  factory CaregiverLink.fromMap(Map<String, dynamic> map, String id) {
    return CaregiverLink(
      id: id,
      senderUid: (map['senderUid'] as String?) ?? '',
      senderName: (map['senderName'] as String?) ?? 'Someone',
      recipientUid: (map['recipientUid'] as String?) ?? '',
      recipientName: (map['recipientName'] as String?) ?? 'User',
      status: CaregiverLinkStatus.values.firstWhere(
        (value) => value.name == map['status'],
        orElse: () => CaregiverLinkStatus.pending,
      ),
      requestedAt: _dateFromMap(map['requestedAt']),
      respondedAt: _optionalDateFromMap(map['respondedAt']),
    );
  }

  Map<String, dynamic> toMap() => {
    'senderUid': senderUid,
    'senderName': senderName,
    'recipientUid': recipientUid,
    'recipientName': recipientName,
    'status': status.name,
    'requestedAt': requestedAt.millisecondsSinceEpoch,
    if (respondedAt != null) 'respondedAt': respondedAt!.millisecondsSinceEpoch,
  };

  static DateTime _dateFromMap(dynamic value) {
    if (value is DateTime) return value;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    return DateTime.now();
  }

  static DateTime? _optionalDateFromMap(dynamic value) {
    if (value is DateTime) return value;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    return null;
  }
}
