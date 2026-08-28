/// The three service-specific emergency dial numbers for a country.
///
/// Many countries route police/ambulance/fire through one shared number
/// (e.g. 911, 112, 999), but several — including Pakistan and India —
/// use distinct numbers per service, so each is tracked separately.
class EmergencyNumbers {
  const EmergencyNumbers({
    required this.police,
    required this.ambulance,
    required this.fire,
  });

  final String police;
  final String ambulance;
  final String fire;
}

class EmergencyNumberService {
  const EmergencyNumberService._();

  static const instance = EmergencyNumberService._();

  /// Returns the police / ambulance / fire dial numbers for the given
  /// locale or country code. Falls back to the universal 112 number for
  /// any country that isn't explicitly mapped.
  EmergencyNumbers emergencyNumbers({String? locale, String? countryCode}) {
    final normalized = (locale ?? countryCode ?? '').toLowerCase();

    if (normalized.contains('pk')) {
      return const EmergencyNumbers(police: '15', ambulance: '1122', fire: '16');
    }
    if (normalized.contains('in')) {
      return const EmergencyNumbers(police: '100', ambulance: '102', fire: '101');
    }
    if (normalized.contains('np')) {
      return const EmergencyNumbers(police: '100', ambulance: '102', fire: '101');
    }
    if (normalized.contains('lk')) {
      return const EmergencyNumbers(police: '119', ambulance: '110', fire: '110');
    }
    if (normalized.contains('bd')) {
      return const EmergencyNumbers(police: '999', ambulance: '999', fire: '999');
    }
    if (normalized.contains('us') || normalized.contains('ca')) {
      return const EmergencyNumbers(police: '911', ambulance: '911', fire: '911');
    }
    if (normalized.contains('au')) {
      return const EmergencyNumbers(police: '000', ambulance: '000', fire: '000');
    }
    if (normalized.contains('gb') || normalized.contains('uk')) {
      return const EmergencyNumbers(police: '999', ambulance: '999', fire: '999');
    }
    if (normalized.contains('de') || normalized.contains('fr') || normalized.contains('es') || normalized.contains('it')) {
      return const EmergencyNumbers(police: '112', ambulance: '112', fire: '112');
    }
    return const EmergencyNumbers(police: '112', ambulance: '112', fire: '112');
  }

  /// Single generic emergency number, kept for any call site that only
  /// needs one number (defaults to the ambulance/medical line, since
  /// this app's SOS flow is health-focused).
  String emergencyDialNumber({String? locale, String? countryCode}) {
    return emergencyNumbers(locale: locale, countryCode: countryCode).ambulance;
  }

  String emergencyLabel({String? locale, String? countryCode}) {
    return 'Emergency services';
  }
}