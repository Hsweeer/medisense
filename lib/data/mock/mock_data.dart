import 'package:latlong2/latlong.dart';

import '../models/models.dart';

/// Frontend-only seed data — a US patient in San Francisco, CA.
///
/// NOTE: the "Nearby care" screen fetches live hospitals/pharmacies from
/// the Overpass API via OverpassService, with FacilityCacheService as an
/// offline fallback — it does NOT read from here.
///
/// `hospitals` below is kept ONLY as a default/fallback for the SOS flow
/// (sos_screen.dart / sos_provider.dart), which needs *some* hospital to
/// pre-select before the user's real location and live nearby data are
/// available.
abstract class MockData {
  static const userName = 'Emily Carter';
  static const userPhone = '(415) 555-0132';

  static const userLocation = LatLng(37.7749, -122.4194);
  static const userLocationLabel = 'San Francisco, CA';

  static const profile = HealthProfile(
    name: userName,
    dob: 'Mar 14, 1991',
    bloodType: 'O+',
    heightIn: 66,
    weightLb: 138,
    allergies: ['Penicillin', 'Peanuts'],
    conditions: ['Mild asthma'],
    medications: ['Albuterol inhaler', 'Vitamin D 2000 IU'],
  );

  // SOS-only fallback hospital list removed. Live data (OverpassService)
  // and FacilityCacheService are used at runtime. Keeping this empty
  // prevents any dummy hospitals being shown by default.
  static final hospitals = <Facility>[];

  static final reminders = <Reminder>[
    Reminder(
      title: 'Albuterol inhaler',
      dose: '2 puffs',
      time: '8:00 AM',
      schedule: 'Daily',
      instructions: 'Before breakfast · shake well',
      status: DoseStatus.taken,
      streakDays: 12,
    ),
    Reminder(
      title: 'Vitamin D',
      dose: '2000 IU · 1 tablet',
      time: '9:00 AM',
      schedule: 'Daily',
      instructions: 'With food',
      streakDays: 6,
    ),
    Reminder(
      title: 'Drink water',
      dose: '8 oz glass',
      time: 'Every 2 hrs',
      schedule: 'Daily',
      streakDays: 3,
    ),
    Reminder(
      title: 'Evening walk',
      dose: '30 minutes',
      time: '6:30 PM',
      schedule: 'Mon · Wed · Fri',
      instructions: 'Light pace is fine',
      streakDays: 2,
    ),
  ];

  static const emergencyContacts = <EmergencyContact>[
    EmergencyContact(
      name: 'Michael Carter',
      relation: 'Spouse',
      phone: '(415) 555-0177',
    ),
    EmergencyContact(
      name: 'Dr. Sarah Nguyen',
      relation: 'Primary care physician',
      phone: '(415) 555-0122',
    ),
  ];

  static const aiSuggestions = [
    'Why am I so tired lately?',
    'Is my headache serious?',
    'Explain my lab report',
    'Allergy-safe cold medicine?',
    'Track my sleep better',
  ];

  static const healthTips = [
    (
      'Hydration check',
      'You logged 3 of 8 glasses today. A glass now keeps you on pace.',
    ),
    (
      'Air quality is moderate',
      'With mild asthma, consider keeping your inhaler handy outdoors today.',
    ),
    (
      'Flu season is here',
      'CVS and Walgreens near you offer walk-in flu shots covered by most plans.',
    ),
  ];
}
