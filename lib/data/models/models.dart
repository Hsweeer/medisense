import 'package:latlong2/latlong.dart';

// ── Chat ────────────────────────────────────────────────────────────────

enum ChatRole { user, ai }

/// Special renderings for an AI reply.
enum ChatCardType { none, sos, prescription, skin }

enum AttachmentType { image, file, voice }

/// What the user intends an attachment to be analyzed as.
enum AttachmentIntent { general, prescription, skin }

class ChatAttachment {
  const ChatAttachment({
    required this.type,
    required this.name,
    this.detail = '',
    this.durationSeconds = 0,
    this.intent = AttachmentIntent.general,
  });

  final AttachmentType type;
  final String name;
  final String detail; // e.g. "2.4 MB · PDF" or "Photo"
  final int durationSeconds; // voice notes only
  final AttachmentIntent intent;
}

class ChatMessage {
  const ChatMessage({
    required this.role,
    required this.text,
    this.card = ChatCardType.none,
    this.attachments = const [],
    this.personalized = false,
  });

  final ChatRole role;
  final String text;
  final ChatCardType card;
  final List<ChatAttachment> attachments;

  /// True when the reply was tailored using the user's health profile.
  final bool personalized;
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
}

// ── Reminders ───────────────────────────────────────────────────────────

enum DoseStatus { pending, taken, snoozed, skipped }

class Reminder {
  Reminder({
    required this.title,
    required this.dose,
    required this.time,
    required this.schedule,
    this.instructions = '',
    this.addedBy = 'you', // 'you' | 'MedAI'
    this.status = DoseStatus.pending,
    this.snoozeLabel,
    this.streakDays = 0,
  });

  final String title;
  String dose;
  String time; // display string, e.g. "8:00 AM"
  String schedule; // "Daily", "Weekdays", "Mon · Wed · Fri"…
  String instructions; // "after food", "with a full glass of water"…
  final String addedBy;
  DoseStatus status;
  String? snoozeLabel; // "rings again 9:10 AM"
  int streakDays;

  bool get taken => status == DoseStatus.taken;
}

// ── Profile / emergency ─────────────────────────────────────────────────

class EmergencyContact {
  const EmergencyContact({
    required this.name,
    required this.relation,
    required this.phone,
  });

  final String name;
  final String relation;
  final String phone;
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
  });

  final String name;
  final String dob;
  final String bloodType;
  final int heightIn; // inches
  final int weightLb; // pounds
  final List<String> allergies;
  final List<String> conditions;
  final List<String> medications;

  String get heightLabel => "${heightIn ~/ 12}'${heightIn % 12}\"";
}
