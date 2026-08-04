import 'dart:convert';

import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../../data/models/models.dart';
import '../config/api_keys.dart';

/// Thrown when the Places API call fails (bad key, no network, quota, etc.)
/// so callers can fall back gracefully instead of crashing the screen.
class PlacesException implements Exception {
  PlacesException(this.message);
  final String message;
  @override
  String toString() => 'PlacesException: $message';
}

/// Wraps Google's Places API (New) — `places:searchNearby` — and maps the
/// response straight onto the app's existing [Facility] model, so the rest
/// of the app (Nearby screen, SOS ride flow, etc.) doesn't need to change.
///
/// One call fetches hospitals AND pharmacies together (Places lets you pass
/// multiple `includedTypes`), along with rating, live open/closed status,
/// and next-open/close time — no separate Place Details call needed.
class PlacesService {
  PlacesService._();

  static final instance = PlacesService._();

  static const _endpoint =
      'https://places.googleapis.com/v1/places:searchNearby';

  // Only ask Google for the fields we actually use — keeps each call on the
  // cheaper "Nearby Search Pro" SKU instead of billing for the full field set.
  static final _fieldMask = [
    'places.id',
    'places.displayName',
    'places.formattedAddress',
    'places.location',
    'places.rating',
    'places.currentOpeningHours.openNow',
    'places.currentOpeningHours.nextCloseTime',
    'places.currentOpeningHours.nextOpenTime',
    'places.internationalPhoneNumber',
    'places.types',
  ].join(',');

  /// Fetches hospitals + pharmacies within [radiusMeters] of [center]
  /// (defaults to 5 km, Google's Nearby Search max is 50 km).
  Future<List<Facility>> nearby({
    required LatLng center,
    double radiusMeters = 5000,
  }) async {
    final apiKey = ApiKeys.googlePlacesApiKey;
    if (apiKey.isEmpty || apiKey == 'PASTE_YOUR_GOOGLE_PLACES_API_KEY_HERE') {
      throw PlacesException('No Google Places API key configured.');
    }

    final response = await http
        .post(
          Uri.parse(_endpoint),
          headers: {
            'Content-Type': 'application/json',
            'X-Goog-Api-Key': apiKey,
            'X-Goog-FieldMask': _fieldMask,
          },
          body: jsonEncode({
            'includedTypes': ['hospital', 'pharmacy'],
            'maxResultCount': 20,
            'locationRestriction': {
              'circle': {
                'center': {
                  'latitude': center.latitude,
                  'longitude': center.longitude,
                },
                'radius': radiusMeters,
              },
            },
          }),
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw PlacesException(
          'Places API error ${response.statusCode}: ${response.body}');
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final rawPlaces = decoded['places'] as List<dynamic>? ?? const [];

    return rawPlaces
        .map((raw) => _toFacility(raw as Map<String, dynamic>, center))
        .whereType<Facility>()
        .toList();
  }

  Facility? _toFacility(Map<String, dynamic> place, LatLng center) {
    final location = place['location'] as Map<String, dynamic>?;
    if (location == null) return null;

    final types =
        (place['types'] as List<dynamic>? ?? const []).map((t) => '$t').toList();
    final isHospital = types.contains('hospital');
    final isPharmacy = types.contains('pharmacy');
    if (!isHospital && !isPharmacy) return null; // ignore stray results

    final position = LatLng(
      (location['latitude'] as num).toDouble(),
      (location['longitude'] as num).toDouble(),
    );

    final hours = place['currentOpeningHours'] as Map<String, dynamic>?;

    final extraTags = types
        .where((t) => !const {
              'hospital',
              'pharmacy',
              'health',
              'point_of_interest',
              'establishment',
              'store',
            }.contains(t))
        .take(2)
        .map(_prettyType)
        .toList();

    return Facility(
      name: (place['displayName']?['text'] as String?) ?? 'Unnamed facility',
      type: isHospital ? FacilityType.hospital : FacilityType.pharmacy,
      address: (place['formattedAddress'] as String?) ?? '',
      position: position,
      // Straight-line distance from the search center; the Nearby screen
      // recomputes this live once a real GPS fix is available.
      distanceMiles:
          Geolocator.distanceBetween(center.latitude, center.longitude,
                  position.latitude, position.longitude) /
              1609.344,
      rating: (place['rating'] as num?)?.toDouble() ?? 0,
      openLabel: _openLabel(hours),
      isOpen: (hours?['openNow'] as bool?) ?? true,
      tags: extraTags,
      phone: (place['internationalPhoneNumber'] as String?) ?? '',
    );
  }

  String _openLabel(Map<String, dynamic>? hours) {
    if (hours == null) return 'Hours unavailable';
    final openNow = hours['openNow'] as bool?;
    final nextClose = hours['nextCloseTime'] as String?;
    final nextOpen = hours['nextOpenTime'] as String?;

    if (openNow == true) {
      // No nextCloseTime while open usually means it never closes.
      return nextClose == null ? 'Open 24 hours' : 'Closes ${_time(nextClose)}';
    }
    if (openNow == false) {
      return nextOpen == null ? 'Closed now' : 'Opens ${_time(nextOpen)}';
    }
    return 'Hours unavailable';
  }

  String _time(String iso) {
    final dt = DateTime.parse(iso).toLocal();
    final hour12 = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final minute = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    return '$hour12:$minute $period';
  }

  String _prettyType(String raw) => raw
      .split('_')
      .where((w) => w.isNotEmpty)
      .map((w) => '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');
}
