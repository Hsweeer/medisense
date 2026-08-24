import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/models/models.dart';

class CachedFacilities {
  final List<Facility> facilities;
  final DateTime fetchedAt;

  CachedFacilities({required this.facilities, required this.fetchedAt});
}

class FacilityCacheService {
  FacilityCacheService._();
  static final instance = FacilityCacheService._();

  static const _keyPrefix = 'facility_cache_';

  String _keyFor(double latitude, double longitude) {
    final roundedLat = latitude.toStringAsFixed(2);
    final roundedLon = longitude.toStringAsFixed(2);
    return '$_keyPrefix${roundedLat}_$roundedLon';
  }

  Future<void> save({
    required double latitude,
    required double longitude,
    required List<Facility> facilities,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    final payload = jsonEncode({
      'fetchedAt': DateTime.now().toIso8601String(),
      'facilities': facilities.map((f) => f.toMap()).toList(),
    });
    await preferences.setString(_keyFor(latitude, longitude), payload);
  }

  Future<CachedFacilities?> load({
    required double latitude,
    required double longitude,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_keyFor(latitude, longitude));
    if (raw == null) return null;

    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final facilities = (decoded['facilities'] as List)
          .map(
            (json) => Facility.fromMap(Map<String, dynamic>.from(json as Map)),
          )
          .toList();
      return CachedFacilities(
        facilities: facilities,
        fetchedAt: DateTime.parse(decoded['fetchedAt'] as String),
      );
    } catch (_) {
      return null;
    }
  }
}
