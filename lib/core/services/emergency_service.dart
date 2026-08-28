class EmergencyNumberService {
  const EmergencyNumberService._();

  static const instance = EmergencyNumberService._();

  String emergencyDialNumber({String? locale, String? countryCode}) {
    final normalized = (locale ?? countryCode ?? '').toLowerCase();

    if (normalized.contains('gb') || normalized.contains('uk')) return '112';
    if (normalized.contains('in')) return '112';
    if (normalized.contains('us') || normalized.contains('ca') || normalized.contains('au')) return '911';
    if (normalized.contains('de') || normalized.contains('fr') || normalized.contains('es') || normalized.contains('it')) return '112';
    if (normalized.contains('pk') || normalized.contains('bd') || normalized.contains('np') || normalized.contains('lk')) return '112';
    return '112';
  }

  String emergencyLabel({String? locale, String? countryCode}) {
    final number = emergencyDialNumber(locale: locale, countryCode: countryCode);
    return number == '911' ? 'Emergency services' : 'Emergency services';
  }
}
