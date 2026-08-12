import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

// ── Chat ────────────────────────────────────────────────────────────────

enum ChatRole { user, ai }

/// Special renderings for an AI reply.
enum ChatCardType { none, sos, prescription, skin }

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
    this.timestamp,
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

  /// When this message was sent. Null for messages not yet round-tripped
  /// through Firestore (e.g. the very first frame before saving completes).
  final DateTime? timestamp;

  Map<String, dynamic> toMap() => {
    'role': role.name,
    'text': text,
    'card': card.name,
    'attachments': attachments.map((a) => a.toMap()).toList(),
    'personalized': personalized,
    'ocrText': ocrText,
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
    this.category = 'medication', // 'medication' | 'measurement' | 'activity'
    this.unit,
    this.forWhom,
    this.conditionTag,
    this.inventoryEnabled = false,
    this.inventoryAmount,
    this.inventoryThreshold,
    this.durationLabel,
  });

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

  // Category-aware fields (added for the 3-tab Add Reminder flow).
  String category; // 'medication' | 'measurement' | 'activity'
  String? unit; // e.g. "pill", "mg", "kg" — medication/measurement
  String? forWhom; // "Myself" or a care-recipient's name — medication only
  String? conditionTag; // "What do you take this for?" — medication only
  bool inventoryEnabled; // refill reminder toggle — medication only
  int? inventoryAmount;
  int? inventoryThreshold;
  String? durationLabel; // e.g. "5 min" — activity only

  bool get taken => status == DoseStatus.taken;

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
      category: map['category'] ?? 'medication',
      unit: map['unit'],
      forWhom: map['forWhom'],
      conditionTag: map['conditionTag'],
      inventoryEnabled: map['inventoryEnabled'] ?? false,
      inventoryAmount: map['inventoryAmount'],
      inventoryThreshold: map['inventoryThreshold'],
      durationLabel: map['durationLabel'],
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
    'category': category,
    if (unit != null) 'unit': unit,
    if (forWhom != null) 'forWhom': forWhom,
    if (conditionTag != null) 'conditionTag': conditionTag,
    'inventoryEnabled': inventoryEnabled,
    if (inventoryAmount != null) 'inventoryAmount': inventoryAmount,
    if (inventoryThreshold != null) 'inventoryThreshold': inventoryThreshold,
    if (durationLabel != null) 'durationLabel': durationLabel,
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
}