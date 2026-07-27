import 'package:latlong2/latlong.dart';

import '../models/models.dart';

/// Frontend-only seed data — a US patient in San Francisco, CA.
abstract class MockData {
  static const userName = 'Emily Carter';
  static const userPhone = '(415) 555-0132';

  /// Default map center — downtown San Francisco.
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

  static final hospitals = <Facility>[
    const Facility(
      name: 'UCSF Medical Center',
      type: FacilityType.hospital,
      address: '505 Parnassus Ave, San Francisco, CA 94143',
      position: LatLng(37.7631, -122.4586),
      distanceMiles: 2.6,
      etaMinutes: 12,
      rating: 4.6,
      openLabel: 'Open 24 hours',
      tags: ['ER', 'Level I Trauma'],
      phone: '(415) 476-1000',
    ),
    const Facility(
      name: 'Zuckerberg SF General Hospital',
      type: FacilityType.hospital,
      address: '1001 Potrero Ave, San Francisco, CA 94110',
      position: LatLng(37.7554, -122.4046),
      distanceMiles: 1.7,
      etaMinutes: 9,
      rating: 4.2,
      openLabel: 'Open 24 hours',
      tags: ['ER', 'Trauma Center'],
      phone: '(628) 206-8000',
    ),
    const Facility(
      name: 'CPMC Van Ness Campus',
      type: FacilityType.hospital,
      address: '1101 Van Ness Ave, San Francisco, CA 94109',
      position: LatLng(37.7867, -122.4212),
      distanceMiles: 0.9,
      etaMinutes: 6,
      rating: 4.5,
      openLabel: 'Open 24 hours',
      tags: ['ER', 'Cardiology'],
      phone: '(415) 600-6000',
    ),
    const Facility(
      name: 'Kaiser Permanente SF',
      type: FacilityType.hospital,
      address: '2425 Geary Blvd, San Francisco, CA 94115',
      position: LatLng(37.7827, -122.4443),
      distanceMiles: 1.8,
      etaMinutes: 10,
      rating: 4.3,
      openLabel: 'ER open 24 hours',
      tags: ['ER', 'Urgent Care'],
      phone: '(415) 833-2000',
    ),
    const Facility(
      name: 'Saint Francis Memorial Hospital',
      type: FacilityType.hospital,
      address: '900 Hyde St, San Francisco, CA 94109',
      position: LatLng(37.7896, -122.4174),
      distanceMiles: 1.1,
      etaMinutes: 7,
      rating: 4.1,
      openLabel: 'Open 24 hours',
      tags: ['ER', 'Burn Center'],
      phone: '(415) 353-6000',
    ),
  ];

  static final pharmacies = <Facility>[
    const Facility(
      name: 'CVS Pharmacy — Market St',
      type: FacilityType.pharmacy,
      address: '731 Market St, San Francisco, CA 94103',
      position: LatLng(37.7867, -122.4043),
      distanceMiles: 0.7,
      rating: 4.0,
      openLabel: 'Open until 10 PM',
      tags: ['24hr photo', 'Vaccines'],
      phone: '(415) 555-0198',
    ),
    const Facility(
      name: 'Walgreens — Van Ness',
      type: FacilityType.pharmacy,
      address: '1301 Franklin St, San Francisco, CA 94109',
      position: LatLng(37.7885, -122.4239),
      distanceMiles: 1.0,
      rating: 4.1,
      openLabel: 'Open 24 hours',
      tags: ['Drive-thru', 'Vaccines'],
      phone: '(415) 555-0143',
    ),
    const Facility(
      name: 'Safeway Pharmacy — Church St',
      type: FacilityType.pharmacy,
      address: '2020 Market St, San Francisco, CA 94114',
      position: LatLng(37.7690, -122.4290),
      distanceMiles: 1.4,
      rating: 4.2,
      openLabel: 'Closes 8 PM',
      tags: ['Rx transfer'],
      phone: '(415) 555-0171',
    ),
    const Facility(
      name: 'Rite Aid — Mission St',
      type: FacilityType.pharmacy,
      address: '2300 Mission St, San Francisco, CA 94110',
      position: LatLng(37.7599, -122.4189),
      distanceMiles: 1.5,
      rating: 3.9,
      openLabel: 'Open until 9 PM',
      tags: ['Wellness clinic'],
      phone: '(415) 555-0155',
    ),
    const Facility(
      name: 'Divisadero Community Pharmacy',
      type: FacilityType.pharmacy,
      address: '908 Divisadero St, San Francisco, CA 94115',
      position: LatLng(37.7776, -122.4382),
      distanceMiles: 1.6,
      rating: 4.8,
      openLabel: 'Closes 7 PM',
      isOpen: true,
      tags: ['Compounding', 'Local'],
      phone: '(415) 555-0119',
    ),
  ];

  static final reminders = <Reminder>[
    Reminder(
        title: 'Albuterol inhaler',
        dose: '2 puffs',
        time: '8:00 AM',
        schedule: 'Daily',
        instructions: 'Before breakfast · shake well',
        status: DoseStatus.taken,
        streakDays: 12),
    Reminder(
        title: 'Vitamin D',
        dose: '2000 IU · 1 tablet',
        time: '9:00 AM',
        schedule: 'Daily',
        instructions: 'With food',
        streakDays: 6),
    Reminder(
        title: 'Drink water',
        dose: '8 oz glass',
        time: 'Every 2 hrs',
        schedule: 'Daily',
        streakDays: 3),
    Reminder(
        title: 'Evening walk',
        dose: '30 minutes',
        time: '6:30 PM',
        schedule: 'Mon · Wed · Fri',
        instructions: 'Light pace is fine',
        streakDays: 2),
  ];

  static const emergencyContacts = <EmergencyContact>[
    EmergencyContact(
        name: 'Michael Carter', relation: 'Spouse', phone: '(415) 555-0177'),
    EmergencyContact(
        name: 'Dr. Sarah Nguyen',
        relation: 'Primary care physician',
        phone: '(415) 555-0122'),
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
