import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

// ── Chat ────────────────────────────────────────────────────────────────

enum ChatRole { user, ai }

/// Special renderings for an AI reply.
enum ChatCardType { none, sos, prescription, skin, heartRate, reminderAdded, quickReplies }

enum AttachmentType { image, file, voice }

/// What the user intends an attachment to be analyzed as.
enum AttachmentIntent { general, prescription, skin }

/// One entry in the MedAI chat-history list (like a ChatGPT/Claude thread).
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
  final String detail; // e.g. "2.4 MB · PDF" or "Photo"
  final int durationSeconds; // voice notes only
  final AttachmentIntent intent;
  final String? filePath; // real on-device file path, when actually captured/picked

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
    this.id, // Firestore document ID, null until saved
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
    this.streaming = false,
  });

  final String? id;
  final ChatRole role;
  final String text;
  final ChatCardType card;
  final List<ChatAttachment> attachments;

  /// True when the reply was tailored using the user's health profile.
  final bool personalized;

  /// Raw text actually read off a scanned prescription photo (real Tesseract
  /// OCR output — not scripted). Null for every other kind of message. The
  /// prescription card re-parses this on demand so the review screen always
  /// works from the real source text, not a cached guess.
  final String? ocrText;

  /// Path to the local photo used for OCR, passed to review screen.
  final String? imagePath;

  /// Raw JSON (as a string) of the real skin-scan server's response for a
  /// skin-check photo. Null for every other kind of message. The skin
  /// report card parses this on demand, same pattern as [ocrText].
  final String? skinScanJson;

  /// Short tappable suggested replies shown under an AI question (e.g.
  /// when MedAI needs a reminder time/frequency and would rather offer
  /// options than guess). Null for every other kind of message.
  final List<String>? quickReplies;

  /// When this message was sent. Null for messages not yet round-tripped
  /// through Firestore (e.g. the very first frame before saving completes).
  final DateTime? timestamp;

  /// True while a streamed AI reply is still receiving tokens — lets the
  /// UI show a live "typing" caret on the bubble itself instead of a
  /// separate spinner, the way ChatGPT-style streaming looks.
  final bool streaming;

  ChatMessage copyWith({String? text, bool? streaming}) => ChatMessage(
    id: id,
    role: role,
    text: text ?? this.text,
    card: card,
    attachments: attachments,
    personalized: personalized,
    ocrText: ocrText,
    imagePath: imagePath,
    skinScanJson: skinScanJson,
    quickReplies: quickReplies,
    timestamp: timestamp,
    streaming: streaming ?? this.streaming,
  );

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
          .map((a) => ChatAttachment.fromMap(Map<String, dynamic>.from(a as Map)))
          .toList(),
      personalized: map['personalized'] ?? false,
      ocrText: map['ocrText'],
      imagePath: map['imagePath'],
      skinScanJson: map['skinScanJson'],
      quickReplies: (map['quickReplies'] as List?)?.map((e) => e.toString()).toList(),
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
  final String openLabel; // "Open 24 hours", "Closes 9 PM"…
  final int etaMinutes; // driving ETA used by the SOS ride flow
  final bool isOpen;
  final List<String> tags; // "ER", "Trauma Center", "Drive-thru"…
  final String phone;

  /// Real straight-line distance in miles from [from] (the user's actual
  /// GPS position) to this facility — used instead of the seeded
  /// [distanceMiles] whenever we have a live location fix.
  double milesFrom(LatLng from) {
    final meters = Geolocator.distanceBetween(
      from.latitude,
      from.longitude,
      position.latitude,
      position.longitude,
    );
    return meters / 1609.344;
  }
}

// ── Reminders ───────────────────────────────────────────────────────────

enum DoseStatus { pending, taken, snoozed, skipped }

class Reminder {
  Reminder({
    this.id, // Firestore document ID, null until saved
    required this.title,
    required this.dose,
    required this.time,
    required this.schedule,
    this.instructions = '',
    this.addedBy = 'you', // 'you' | 'MedAI'
    this.status = DoseStatus.pending,
    this.snoozeLabel,
    this.streakDays = 0,
    this.enabled = true,
    this.groupId,
    DateTime? lastStatusDate,
  }) : lastStatusDate = lastStatusDate ?? DateTime.now();

  String? id; // Firestore document ID
  final String title;
  String dose;
  String time; // display string, e.g. "8:00 AM"
  String schedule; // "Daily", "Weekdays", "Mon · Wed · Fri"…
  String instructions; // "after food", "with a full glass of water"…
  final String addedBy;
  DoseStatus status;
  String? snoozeLabel; // "rings again 9:10 AM"
  int streakDays;
  bool enabled; // controls whether alarm is scheduled

  /// Links multiple dose-times of the SAME medicine (e.g. a prescription
  /// that's "3 times a day") so the Reminders screen can show them as one
  /// grouped card instead of separate cards for what is really one
  /// medicine. Null for single-dose reminders, which don't need grouping.
  final String? groupId;

  /// The calendar day [status] applies to. A dose marked "taken" only
  /// stays taken for that one day — this is what lets the app tell the
  /// difference between "taken today" and "was taken yesterday, should be
  /// pending (and re-alarmed) again today."
  DateTime lastStatusDate;

  bool get taken => status == DoseStatus.taken;

  /// True when [lastStatusDate] is not today — meaning this reminder's
  /// status is stale from a previous day and needs resetting.
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
    'lastStatusDateMs': lastStatusDate.millisecondsSinceEpoch,
  };
}

// ── AI Insights (personalized data learned from MedAI chat) ─────────────

/// A short personalized fact MedAI picked up during a conversation —
/// e.g. a recurring symptom, a health concern, or a preference — so the
/// profile screen can show "what MedAI has learned about you" instead of
/// that context living only inside old chat threads.
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

  /// Firestore document id — null until it's been saved.
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

// ── "For you" personalized AI advice (home screen) ───────────────────────

/// One personalized piece of health advice generated from the user's
/// health profile + what MedAI has learned from chat — shown on the home
/// screen the way a professional health app's "For you" card works,
/// instead of a static generic tip.
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
  final int heightIn; // inches
  final int weightLb; // pounds
  final List<String> allergies;
  final List<String> conditions;
  final List<String> medications;

  /// Download URL of the user's profile photo in Firebase Storage.
  /// Null (or empty) means no photo has been set — UI falls back to
  /// initials avatar in that case.
  final String? imageUrl;

  String get heightLabel => "${heightIn ~/ 12}'${heightIn % 12}\"";

  /// Used while data is still loading, or before Firestore has anything.
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

  /// Written once, the first time a new user's profile doc is created.
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
    if (now.month < date.month || (now.month == date.month && now.day < date.day)) {
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

enum HeartRateZone {
  belowTypical,
  normal,
  aboveTypical,
}

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