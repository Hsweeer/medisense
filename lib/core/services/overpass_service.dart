// lib/core/services/overpass_service.dart

import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../../data/models/models.dart';

class OverpassAllEndpointsFailedException implements Exception {
  @override
  String toString() => 'All Overpass endpoints failed or timed out.';
}

class OverpassService {
  OverpassService._();
  static final instance = OverpassService._();

  /// Reads the endpoint list from .env, falling back to the known-good
  /// public defaults if a key is missing or the .env value is empty —
  /// so a misconfigured .env never leaves this list empty.
  List<String> get _endpoints {
    final fromEnv = [
      dotenv.env['OVERPASS_ENDPOINT_PRIMARY'],
      dotenv.env['OVERPASS_ENDPOINT_FALLBACK_1'],
      dotenv.env['OVERPASS_ENDPOINT_FALLBACK_2'],
    ].whereType<String>().where((e) => e.trim().isNotEmpty).toList();

    if (fromEnv.isNotEmpty) return fromEnv;

    // Safety net — same defaults as before, used only if .env is missing
    // or these specific keys weren't set.
    return const [
      'https://overpass-api.de/api/interpreter',
      'https://overpass.kumi.systems/api/interpreter',
      'https://overpass.private.coffee/api/interpreter',
    ];
  }

  static const _requestTimeout = Duration(seconds: 15);

  Future<List<Facility>> fetchNearby({
    required double latitude,
    required double longitude,
    required LatLng userPosition,
    double radiusMeters = 5000,
  }) async {
    final query = _buildQuery(
      radiusMeters: radiusMeters,
      latitude: latitude,
      longitude: longitude,
    );

    for (final endpoint in _endpoints) {
      try {
        final response = await http
            .post(Uri.parse(endpoint), body: {'data': query})
            .timeout(_requestTimeout);

        if (response.statusCode == 200) {
          return _parseResponse(response.body, userPosition);
        }
      } catch (_) {
        continue;
      }
    }

    throw OverpassAllEndpointsFailedException();
  }

  String _buildQuery({
    required double radiusMeters,
    required double latitude,
    required double longitude,
  }) {
    return '''
[out:json][timeout:25];
(
  node["amenity"~"^(hospital|pharmacy)\$"](around:$radiusMeters,$latitude,$longitude);
  way["amenity"~"^(hospital|pharmacy)\$"](around:$radiusMeters,$latitude,$longitude);
  relation["amenity"~"^(hospital|pharmacy)\$"](around:$radiusMeters,$latitude,$longitude);
);
out center;
''';
  }

  List<Facility> _parseResponse(String body, LatLng userPosition) {
    final decoded = jsonDecode(body) as Map<String, dynamic>;
    final elements = (decoded['elements'] as List?) ?? const [];

    final facilities = <Facility>[];
    for (final raw in elements) {
      final facility = _fromOverpassElement(
        raw as Map<String, dynamic>,
        userPosition,
      );
      if (facility != null) facilities.add(facility);
    }
    return facilities;
  }

  Facility? _fromOverpassElement(
    Map<String, dynamic> element,
    LatLng userPosition,
  ) {
    final tags = (element['tags'] as Map?)?.cast<String, dynamic>() ?? const {};

    final amenity = tags['amenity'] as String?;
    final FacilityType? type = switch (amenity) {
      'hospital' => FacilityType.hospital,
      'pharmacy' => FacilityType.pharmacy,
      _ => null,
    };
    if (type == null) return null;

    final double? lat =
        (element['lat'] as num?)?.toDouble() ??
        ((element['center'] as Map?)?['lat'] as num?)?.toDouble();
    final double? lon =
        (element['lon'] as num?)?.toDouble() ??
        ((element['center'] as Map?)?['lon'] as num?)?.toDouble();
    if (lat == null || lon == null) return null;

    final position = LatLng(lat, lon);

    final rawName = (tags['name'] as String?)?.trim();
    final fallbackName = type == FacilityType.hospital
        ? 'Unnamed Hospital'
        : 'Unnamed Pharmacy';
    final name = (rawName == null || rawName.isEmpty) ? fallbackName : rawName;

    const rating = 0.0;

    final openingHours = tags['opening_hours'] as String?;
    final openLabel = (openingHours == null || openingHours.isEmpty)
        ? 'Hours not listed'
        : (openingHours.contains('24/7') ? 'Open 24 hours' : openingHours);

    final phone = (tags['phone'] ?? tags['contact:phone'] ?? '') as String;

    final address = _buildAddress(tags);

    final tagList = <String>[
      if (tags['emergency'] == 'yes') 'ER',
      if (type == FacilityType.pharmacy && tags['drive_through'] == 'yes')
        'Drive-thru',
    ];

    final distanceMiles =
        Geolocator.distanceBetween(
          userPosition.latitude,
          userPosition.longitude,
          position.latitude,
          position.longitude,
        ) /
        1609.344;

    return Facility(
      name: name,
      type: type,
      address: address,
      position: position,
      distanceMiles: distanceMiles,
      rating: rating,
      openLabel: openLabel,
      etaMinutes: 0,
      isOpen: true,
      tags: tagList,
      phone: phone,
    );
  }

  String _buildAddress(Map<String, dynamic> tags) {
    final houseNumber = tags['addr:housenumber'] as String?;
    final street = tags['addr:street'] as String?;
    final city = tags['addr:city'] as String?;

    final parts = [
      if (houseNumber != null && street != null) '$houseNumber $street',
      city,
    ].whereType<String>().where((p) => p.trim().isNotEmpty);

    return parts.isEmpty ? 'Address not listed' : parts.join(', ');
  }
}
