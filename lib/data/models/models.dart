import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

// ── Chat ────────────────────────────────────────────────────────────────

enum ChatRole { user, ai }

enum ChatCardType {
  none,
  sos,
  prescription,
  skin,
  heartRate,
  reminderAdded,
  quickReplies,
}

enum AttachmentType { image, file, voice }

enum AttachmentIntent { general, prescription, skin }

class ChatConversationSummary {
  const ChatConversationSummary({
    required this.id,
    required this.title,
    required this.lastMessagePreview,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final String lastMessagePreview;
  final DateTime updatedAt;

  factory ChatConversationSummary.fromMap(Map<String, dynamic> map, String id) {
    return ChatConversationSummary(
      id: id,
      title: (map['title'] as String?)?.trim().isNotEmpty == true
          ? map['title']
          : 'New chat',
      lastMessagePreview: map['lastMessagePreview'] ?? '',
      updatedAt: map['updatedAtMs'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['updatedAtMs'])
          : DateTime.now(),
    );
  }
}

class ChatAttachment {
  const ChatAttachment({
    required this.type,
    required this.name,
    this.detail = '',
    this.durationSeconds = 0,
    this.intent = AttachmentIntent.general,
    this.filePath,
  });

  final AttachmentType type;
  final String name;
  final String detail;
  final int durationSeconds;
  final AttachmentIntent intent;
  final String? filePath;

  Map<String, dynamic> toMap() => {
    'type': type.name,
    'name': name,
    'detail': detail,
    'durationSeconds': durationSeconds,
    'intent': intent.name,
    'filePath': filePath,
  };

  factory ChatAttachment.fromMap(Map<String, dynamic> map) => ChatAttachment(
    type: AttachmentType.values.firstWhere(
      (e) => e.name == map['type'],
      orElse: () => AttachmentType.image,
    ),
    name: map['name'] ?? '',
    detail: map['detail'] ?? '',
    durationSeconds: map['durationSeconds'] ?? 0,
    intent: AttachmentIntent.values.firstWhere(
      (e) => e.name == map['intent'],
      orElse: () => AttachmentIntent.general,
    ),
    filePath: map['filePath'],
  );
}

class ChatMessage {
  const ChatMessage({
    this.id,
    required this.role,
    required this.text,
    this.card = ChatCardType.none,
    this.attachments = const [],
    this.personalized = false,
    this.ocrText,
    this.imagePath,
    this.skinScanJson,
    this.quickReplies,
    this.timestamp,
  });

  final String? id;
  final ChatRole role;
  final String text;
  final ChatCardType card;
  final List<ChatAttachment> attachments;
  final bool personalized;
  final String? ocrText;
  final String? imagePath;
  final String? skinScanJson;
  final List<String>? quickReplies;
  final DateTime? timestamp;

  Map<String, dynamic> toMap() => {
    'role': role.name,
    'text': text,
    'card': card.name,
    'attachments': attachments.map((a) => a.toMap()).toList(),
    'personalized': personalized,
    'ocrText': ocrText,
    'imagePath': imagePath,
    'skinScanJson': skinScanJson,
    'quickReplies': quickReplies,
    'timestampMs': (timestamp ?? DateTime.now()).millisecondsSinceEpoch,
  };

  factory ChatMessage.fromMap(Map<String, dynamic> map, String id) {
    return ChatMessage(
      id: id,
      role: ChatRole.values.firstWhere(
        (e) => e.name == map['role'],
        orElse: () => ChatRole.ai,
      ),
      text: map['text'] ?? '',
      card: ChatCardType.values.firstWhere(
        (e) => e.name == map['card'],
        orElse: () => ChatCardType.none,
      ),
      attachments: ((map['attachments'] as List?) ?? [])
          .map(
            (a) => ChatAttachment.fromMap(Map<String, dynamic>.from(a as Map)),
          )
          .toList(),
      personalized: map['personalized'] ?? false,
      ocrText: map['ocrText'],
      imagePath: map['imagePath'],
      skinScanJson: map['skinScanJson'],
      quickReplies: (map['quickReplies'] as List?)
          ?.map((e) => e.toString())
          .toList(),
      timestamp: map['timestampMs'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['timestampMs'])
          : null,
    );
  }
}

// ── Nearby care ─────────────────────────────────────────────────────────

enum FacilityType { hospital, pharmacy }

class Facility {
  const Facility({
    required this.name,
    required this.type,
    required this.address,
    required this.position,
    required this.distanceMiles,
    required this.rating,
    required this.openLabel,
    this.etaMinutes = 0,
    this.isOpen = true,
    this.tags = const [],
    this.phone = '',
  });

  final String name;
  final FacilityType type;
  final String address;
  final LatLng position;
  final double distanceMiles;
  final double rating;
  final String openLabel;
  final int etaMinutes;
  final bool isOpen;
  final List<String> tags;
  final String phone;

  double milesFrom(LatLng from) {
    final meters = Geolocator.distanceBetween(
      from.latitude,
      from.longitude,
      position.latitude,
      position.longitude,
    );
    return meters / 1609.344;
  }

  Map<String, dynamic> toMap() => {
    'name': name,
    'type': type.name,
    'address': address,
    'lat': position.latitude,
    'lon': position.longitude,
    'distanceMiles': distanceMiles,
    'rating': rating,
    'openLabel': openLabel,
    'etaMinutes': etaMinutes,
    'isOpen': isOpen,
    'tags': tags,
    'phone': phone,
  };

  factory Facility.fromMap(Map<String, dynamic> map) => Facility(
    name: map['name'] ?? '',
    type: FacilityType.values.firstWhere(
      (e) => e.name == map['type'],
      orElse: () => FacilityType.hospital,
    ),
    address: map['address'] ?? '',
    position: LatLng(
      (map['lat'] as num).toDouble(),
      (map['lon'] as num).toDouble(),
    ),
    distanceMiles: (map['distanceMiles'] as num?)?.toDouble() ?? 0,
    rating: (map['rating'] as num?)?.toDouble() ?? 0,
    openLabel: map['openLabel'] ?? '',
    etaMinutes: map['etaMinutes'] ?? 0,
    isOpen: map['isOpen'] ?? true,
    tags: List<String>.from(map['tags'] ?? const []),
    phone: map['phone'] ?? '',
  );
}

// ── Reminders ───────────────────────────────────────────────────────────

enum DoseStatus { pending, taken, snoozed, skipped }

class Reminder {
  Reminder({
    this.id,
    required this.title,
    required this.dose,
    required this.time,
    required this.schedule,
    this.instructions = '',
    this.addedBy = 'you',
    this.status = DoseStatus.pending,
    this.snoozeLabel,
    this.streakDays = 0,
    this.enabled = true,
    this.groupId,
    this.createdByUid,
    DateTime? lastStatusDate,
  }) : lastStatusDate = lastStatusDate ?? DateTime.now();

  String? id;
  final String title;
  String dose;
  String time;
  String schedule;
  String instructions;
  final String addedBy;
  DoseStatus status;
  String? snoozeLabel;
  int streakDays;
  bool enabled;
  final String? groupId;

  /// UID of the caregiver who created this reminder for someone else.
  /// Null when the reminder was self-created. Used by the Caregiver
  /// Reminder Sharing feature to grant edit/delete rights back to the
  /// original sender, and to find/cancel their reminders on revoke.
  final String? createdByUid;

  DateTime lastStatusDate;

  bool get taken => status == DoseStatus.taken;

  bool get isStatusStale {
    final now = DateTime.now();
    return lastStatusDate.year != now.year ||
        lastStatusDate.month != now.month ||
        lastStatusDate.day != now.day;
  }

  factory Reminder.fromMap(Map<String, dynamic> map, String id) {
    return Reminder(
      id: id,
      title: map['title'] ?? '',
      dose: map['dose'] ?? '',
      time: map['time'] ?? '9:00 AM',
      schedule: map['schedule'] ?? 'Daily',
      instructions: map['instructions'] ?? '',
      addedBy: map['addedBy'] ?? 'you',
      status: DoseStatus.values.firstWhere(
        (e) => e.toString() == 'DoseStatus.${map['status'] ?? 'pending'}',
        orElse: () => DoseStatus.pending,
      ),
      snoozeLabel: map['snoozeLabel'],
      streakDays: map['streakDays'] ?? 0,
      enabled: map['enabled'] ?? true,
      groupId: map['groupId'],
      createdByUid: map['createdByUid'],
      lastStatusDate: map['lastStatusDateMs'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['lastStatusDateMs'])
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
    'title': title,
    'dose': dose,
    'time': time,
    'schedule': schedule,
    'instructions': instructions,
    'addedBy': addedBy,
    'status': status.toString().split('.').last,
    'streakDays': streakDays,
    'enabled': enabled,
    'groupId': groupId,
    'createdByUid': createdByUid,
    'lastStatusDateMs': lastStatusDate.millisecondsSinceEpoch,
  };
}

// ── AI Insights ───────────────────────────────────────────────────────

enum AiInsightType { symptom, concern, preference, note }

class AiInsight {
  const AiInsight({
    this.id,
    required this.type,
    required this.text,
    required this.createdAt,
    this.conversationId,
  });

  final String? id;
  final AiInsightType type;
  final String text;
  final DateTime createdAt;
  final String? conversationId;

  factory AiInsight.fromMap(Map<String, dynamic> map, String id) {
    return AiInsight(
      id: id,
      type: AiInsightType.values.firstWhere(
        (e) => e.name == map['type'],
        orElse: () => AiInsightType.note,
      ),
      text: map['text'] ?? '',
      createdAt: map['createdAtMs'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['createdAtMs'])
          : DateTime.now(),
      conversationId: map['conversationId'],
    );
  }

  Map<String, dynamic> toMap() => {
    'type': type.name,
    'text': text,
    'createdAtMs': DateTime.now().millisecondsSinceEpoch,
    'conversationId': conversationId,
  };
}

// ── Profile / emergency ─────────────────────────────────────────────────

class EmergencyContact {
  const EmergencyContact({
    this.id,
    required this.name,
    required this.relation,
    required this.phone,
  });

  final String? id;
  final String name;
  final String relation;
  final String phone;

  factory EmergencyContact.fromMap(Map<String, dynamic> map, String id) {
    return EmergencyContact(
      id: id,
      name: map['name'] ?? '',
      relation: map['relation'] ?? 'Contact',
      phone: map['phone'] ?? '',
    );
  }

  Map<String, dynamic> toMap() => {
    'name': name,
    'relation': relation,
    'phone': phone,
  };
}

class ForYouTip {
  const ForYouTip({
    required this.title,
    required this.body,
    required this.generatedAt,
  });

  final String title;
  final String body;
  final DateTime generatedAt;

  factory ForYouTip.fromMap(Map<String, dynamic> map) => ForYouTip(
    title: map['title'] ?? '',
    body: map['body'] ?? '',
    generatedAt: map['generatedAtMs'] != null
        ? DateTime.fromMillisecondsSinceEpoch(map['generatedAtMs'])
        : DateTime.now(),
  );

  Map<String, dynamic> toMap() => {
    'title': title,
    'body': body,
    'generatedAtMs': generatedAt.millisecondsSinceEpoch,
  };
}

class HealthProfile {
  const HealthProfile({
    required this.name,
    required this.dob,
    required this.bloodType,
    required this.heightIn,
    required this.weightLb,
    required this.allergies,
    required this.conditions,
    required this.medications,
    this.imageUrl,
  });

  final String name;
  final String dob;
  final String bloodType;
  final int heightIn;
  final int weightLb;
  final List<String> allergies;
  final List<String> conditions;
  final List<String> medications;
  final String? imageUrl;

  String get heightLabel => "${heightIn ~/ 12}'${heightIn % 12}\"";

  factory HealthProfile.empty() => const HealthProfile(
    name: '',
    dob: '',
    bloodType: '—',
    heightIn: 0,
    weightLb: 0,
    allergies: [],
    conditions: [],
    medications: [],
    imageUrl: null,
  );

  factory HealthProfile.starter({required String name}) => HealthProfile(
    name: name,
    dob: '',
    bloodType: '—',
    heightIn: 0,
    weightLb: 0,
    allergies: const [],
    conditions: const [],
    medications: const [],
    imageUrl: null,
  );

  factory HealthProfile.fromMap(Map<String, dynamic> map) => HealthProfile(
    name: map['name'] ?? '',
    dob: map['dob'] ?? '',
    bloodType: map['bloodType'] ?? '—',
    heightIn: map['heightIn'] ?? 0,
    weightLb: map['weightLb'] ?? 0,
    allergies: List<String>.from(map['allergies'] ?? const []),
    conditions: List<String>.from(map['conditions'] ?? const []),
    medications: List<String>.from(map['medications'] ?? const []),
    imageUrl: map['profileImage'] as String?,
  );

  Map<String, dynamic> toMap() => {
    'name': name,
    'dob': dob,
    'bloodType': bloodType,
    'heightIn': heightIn,
    'weightLb': weightLb,
    'allergies': allergies,
    'conditions': conditions,
    'medications': medications,
    'profileImage': imageUrl,
  };

  HealthProfile copyWith({
    String? name,
    String? dob,
    String? bloodType,
    int? heightIn,
    int? weightLb,
    List<String>? allergies,
    List<String>? conditions,
    List<String>? medications,
    String? imageUrl,
  }) {
    return HealthProfile(
      name: name ?? this.name,
      dob: dob ?? this.dob,
      bloodType: bloodType ?? this.bloodType,
      heightIn: heightIn ?? this.heightIn,
      weightLb: weightLb ?? this.weightLb,
      allergies: allergies ?? this.allergies,
      conditions: conditions ?? this.conditions,
      medications: medications ?? this.medications,
      imageUrl: imageUrl ?? this.imageUrl,
    );
  }

  int? get ageYears {
    if (dob.trim().isEmpty) return null;
    final date = _parseDob(dob);
    if (date == null) return null;
    final now = DateTime.now();
    var years = now.year - date.year;
    if (now.month < date.month ||
        (now.month == date.month && now.day < date.day)) {
      years--;
    }
    return years;
  }

  DateTime? _parseDob(String value) {
    final cleaned = value.trim();
    if (cleaned.isEmpty) return null;

    try {
      final parts = cleaned.contains('/')
          ? cleaned.split('/')
          : cleaned.contains('-')
          ? cleaned.split('-')
          : null;
      if (parts != null && parts.length == 3) {
        final first = int.tryParse(parts[0]);
        final second = int.tryParse(parts[1]);
        final third = int.tryParse(parts[2]);
        if (first != null && second != null && third != null) {
          if (cleaned.contains('/')) {
            return DateTime(third, first, second);
          }
          return DateTime(third, second, first);
        }
      }
      return DateTime.tryParse(cleaned);
    } catch (_) {
      return null;
    }
  }
}

enum HeartRateZone { belowTypical, normal, aboveTypical }

extension HeartRateZoneX on HeartRateZone {
  String get label {
    switch (this) {
      case HeartRateZone.belowTypical:
        return 'Below typical resting range';
      case HeartRateZone.normal:
        return 'Normal resting range';
      case HeartRateZone.aboveTypical:
        return 'Above typical resting range';
    }
  }
}

class HeartRateReading {
  const HeartRateReading({required this.bpm});

  final double bpm;

  static HeartRateZone classify(double bpm) {
    if (bpm < 60) return HeartRateZone.belowTypical;
    if (bpm <= 100) return HeartRateZone.normal;
    return HeartRateZone.aboveTypical;
  }

  HeartRateZone get zone => classify(bpm);

  String get zoneLabel => zone.label;

  String get summaryLine => '${bpm.round()} BPM · $zoneLabel';

  String personalizedContext(HealthProfile? profile) {
    final age = profile?.ageYears;
    if (age == null) {
      return 'This estimate is useful as a quick check, but it is not a medical device.';
    }
    if (zone == HeartRateZone.normal) {
      return 'Aapki age ke hisaab se ye normal range mein hai.';
    }
    if (zone == HeartRateZone.belowTypical) {
      return 'Aapki age ke hisaab se ye lower than typical resting range hai.';
    }
    return 'Aapki age ke hisaab se ye higher than typical resting range hai.';
  }

  static String zoneLabelForBpm(double bpm) => classify(bpm).label;
}
