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

  // Bump this whenever the shape or meaning of cached fields changes (e.g.
  // the open/closed label logic). Old entries written under a previous
  // version are treated as absent so the app is forced to re-fetch live
  // data instead of showing stale labels forever from local storage.
  static const _cacheVersion = 2;

  String _keyFor(double latitude, double longitude) {
    final roundedLat = latitude.toStringAsFixed(3);
    final roundedLon = longitude.toStringAsFixed(3);
    return '$_keyPrefix${roundedLat}_$roundedLon';
  }

  Future<void> save({
    required double latitude,
    required double longitude,
    required List<Facility> facilities,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    final payload = jsonEncode({
      'version': _cacheVersion,
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
      // Stale cache written before a data-shape change (e.g. old-style
      // openLabel text) -- discard it and let the caller re-fetch live.
      if (decoded['version'] != _cacheVersion) return null;

      // Skip individual bad entries instead of Facility.fromMap throwing
      // and discarding the entire cached list over one corrupt record.
      final facilities = <Facility>[];
      for (final json in (decoded['facilities'] as List)) {
        try {
          facilities.add(
            Facility.fromMap(Map<String, dynamic>.from(json as Map)),
          );
        } catch (_) {
          continue;
        }
      }
      return CachedFacilities(
        facilities: facilities,
        fetchedAt: DateTime.parse(decoded['fetchedAt'] as String),
      );
    } catch (_) {
      return null;
    }
  }
}