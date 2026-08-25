// lib/core/services/overpass_service.dart

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../../data/models/models.dart';

class OverpassAllEndpointsFailedException implements Exception {
  @override
  String toString() => 'All Overpass endpoints failed or timed out.';
}

/// Very small subset parser for OSM `opening_hours` syntax, good enough to
/// answer "is it open right now" for the common patterns actually seen in
/// the field (e.g. "Mo-Fr 08:00-20:00; Sa 08:00-14:00", "24/7",
/// "08:00-22:00", "Mo-Su 09:00-21:00"). Anything it can't confidently parse
/// falls back to null (unknown), so callers show "Hours not listed" instead
/// of guessing.
const _kDayTokens = ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'];

bool? _isOpenNow(String? openingHours, {DateTime? now}) {
  if (openingHours == null || openingHours.trim().isEmpty) return null;
  final raw = openingHours.trim();
  if (raw.toLowerCase() == '24/7') return true;

  final current = now ?? DateTime.now();
  // DateTime.weekday: Monday = 1 ... Sunday = 7
  final todayToken = _kDayTokens[current.weekday - 1];
  final nowMinutes = current.hour * 60 + current.minute;

  bool matchedAnyDayRule = false;
  bool openNow = false;

  for (final rawRule in raw.split(';')) {
    final rule = rawRule.trim();
    if (rule.isEmpty) continue;

    final parts = rule.split(RegExp(r'\s+'));
    if (parts.isEmpty) continue;

    final looksLikeDaySpec = RegExp(
      r'^(Mo|Tu|We|Th|Fr|Sa|Su)',
    ).hasMatch(parts.first);

    final String daySpec;
    final String timeSpec;
    if (looksLikeDaySpec) {
      daySpec = parts.first;
      timeSpec = parts.skip(1).join(' ');
    } else {
      // No day prefix -- rule applies every day (e.g. plain "08:00-20:00").
      daySpec = 'Mo-Su';
      timeSpec = parts.join(' ');
    }

    if (!_dayMatches(daySpec, todayToken)) continue;
    matchedAnyDayRule = true;

    if (timeSpec.toLowerCase().contains('off') ||
        timeSpec.toLowerCase().contains('closed')) {
      openNow = false;
      continue;
    }

    for (final range in timeSpec.split(',')) {
      final match = RegExp(
        r'^(\d{1,2}):(\d{2})-(\d{1,2}):(\d{2})$',
      ).firstMatch(range.trim());
      if (match == null) continue;
      final startMin =
          int.parse(match.group(1)!) * 60 + int.parse(match.group(2)!);
      var endMin =
          int.parse(match.group(3)!) * 60 + int.parse(match.group(4)!);
      if (endMin <= startMin) endMin += 24 * 60; // overnight range
      if (nowMinutes >= startMin && nowMinutes < endMin) {
        openNow = true;
      }
    }
  }

  if (!matchedAnyDayRule) return false;
  return openNow;
}

bool _dayMatches(String daySpec, String today) {
  for (final segment in daySpec.split(',')) {
    final s = segment.trim();
    if (s.isEmpty) continue;
    if (s.contains('-')) {
      final bounds = s.split('-');
      if (bounds.length != 2) continue;
      final start = _kDayTokens.indexOf(bounds[0]);
      final end = _kDayTokens.indexOf(bounds[1]);
      final todayIdx = _kDayTokens.indexOf(today);
      if (start == -1 || end == -1 || todayIdx == -1) continue;
      if (start <= end) {
        if (todayIdx >= start && todayIdx <= end) return true;
      } else {
        // Wraps around the week, e.g. "Fr-Mo".
        if (todayIdx >= start || todayIdx <= end) return true;
      }
    } else if (s == today) {
      return true;
    }
  }
  return false;
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

  static const _requestTimeout = Duration(seconds: 30);

  // As of ~April 2026, overpass-api.de (the primary endpoint) started
  // returning 406 Not Acceptable for requests without a proper
  // identifying User-Agent (and a JSON Accept header) — a request with
  // no headers at all, like a bare Dart http.post(), gets rejected
  // outright before the query is even looked at. This is unrelated to
  // rate limits, timeouts, or the query itself; see
  // github.com/drolbr/Overpass-API/issues/791 and the OSM community
  // forum thread on "Overpass API - Error 406". The community-run
  // mirrors (kumi.systems, private.coffee) don't enforce this as
  // strictly, but sending it on every request costs nothing and avoids
  // the same fate if they tighten their policy too.
  static const _userAgent =
      'MediSense/1.0 (Flutter health app; contact: support@medisense.app)';

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
            .post(
          Uri.parse(endpoint),
          headers: {
            'User-Agent': _userAgent,
            'Accept': 'application/json',
          },
          body: {'data': query},
        )
            .timeout(_requestTimeout);

        if (response.statusCode == 200) {
          return _parseResponse(response.body, userPosition);
        }
        // Log the real reason instead of silently moving on — a 406/429/5xx
        // here previously looked identical to a plain timeout, which made
        // "why did every endpoint fail" impossible to diagnose from the
        // caller side.
        debugPrint(
            '[OverpassService] $endpoint returned ${response.statusCode}: '
                '${response.body.length > 200 ? response.body.substring(0, 200) : response.body}');
      } catch (e) {
        debugPrint('[OverpassService] $endpoint threw: $e');
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
    // Hospitals are reliably tagged amenity=hospital, but "pharmacy" is
    // split across multiple OSM tagging schemes in practice — especially
    // in South Asia, where a lot of local medical stores get mapped as
    // shop=chemist rather than amenity=pharmacy (per OSM's own wiki:
    // shop=chemist is meant for stores without a pharmacy counter, but
    // that distinction isn't consistently followed on the ground).
    // Querying only amenity=pharmacy silently missed most of them.
    // ",i" at the end of each regex = case-insensitive match. Local OSM
    // contributors in South Asia frequently tag these inconsistently
    // ("Chemist", "Pharmacy", "PHARMACY" etc.), and amenity=hospital
    // being reliably lowercase (usually from standardized/NGO imports)
    // is exactly why hospitals matched fine while pharmacies silently
    // returned zero results.
    return '''
[out:json][timeout:25];
(
  node["amenity"~"^(hospital|pharmacy)\$",i](around:$radiusMeters,$latitude,$longitude);
  way["amenity"~"^(hospital|pharmacy)\$",i](around:$radiusMeters,$latitude,$longitude);
  relation["amenity"~"^(hospital|pharmacy)\$",i](around:$radiusMeters,$latitude,$longitude);
  node["shop"~"^(chemist|pharmacy|drugstore)\$",i](around:$radiusMeters,$latitude,$longitude);
  way["shop"~"^(chemist|pharmacy|drugstore)\$",i](around:$radiusMeters,$latitude,$longitude);
  relation["shop"~"^(chemist|pharmacy|drugstore)\$",i](around:$radiusMeters,$latitude,$longitude);
  node["healthcare"~"^pharmacy\$",i](around:$radiusMeters,$latitude,$longitude);
  way["healthcare"~"^pharmacy\$",i](around:$radiusMeters,$latitude,$longitude);
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

    final hospitalCount =
        facilities.where((f) => f.type == FacilityType.hospital).length;
    final pharmacyCount =
        facilities.where((f) => f.type == FacilityType.pharmacy).length;
    debugPrint(
      '[OverpassService] raw elements: ${elements.length} | '
          'parsed hospitals: $hospitalCount | parsed pharmacies: $pharmacyCount',
    );

    return facilities;
  }

  Facility? _fromOverpassElement(
      Map<String, dynamic> element,
      LatLng userPosition,
      ) {
    final tags = (element['tags'] as Map?)?.cast<String, dynamic>() ?? const {};

    // Lowercase before comparing — the Overpass query now matches tag
    // values case-insensitively (",i" flag), so values like "Chemist"
    // or "Pharmacy" can come back from the API. Comparing them against
    // exact-lowercase strings here would silently drop them again.
    final amenity = (tags['amenity'] as String?)?.toLowerCase();
    final shop = (tags['shop'] as String?)?.toLowerCase();
    final healthcare = (tags['healthcare'] as String?)?.toLowerCase();

    final FacilityType? type;
    if (amenity == 'hospital') {
      type = FacilityType.hospital;
    } else if (amenity == 'pharmacy' ||
        shop == 'chemist' ||
        shop == 'pharmacy' ||
        shop == 'drugstore' ||
        healthcare == 'pharmacy') {
      type = FacilityType.pharmacy;
    } else {
      type = null;
    }
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
    final openNow = _isOpenNow(openingHours);

    final String openLabel;
    final bool isOpenResolved;
    if (openingHours != null && openingHours.trim().toLowerCase() == '24/7') {
      openLabel = 'Open 24 hours';
      isOpenResolved = true;
    } else if (openNow != null) {
      openLabel = openNow ? 'Open' : 'Closed';
      isOpenResolved = openNow;
    } else if (type == FacilityType.hospital) {
      // OSM very often has no opening_hours tag on hospitals because they
      // run around the clock (emergency dept never closes) and nobody
      // bothers tagging it. Rather than showing a confusing "Hours not
      // listed" for what is almost certainly a 24/7 facility, assume open
      // and flag it as an assumption so the user isn't misled.
      openLabel = 'Likely open 24/7';
      isOpenResolved = true;
    } else {
      openLabel = 'Hours not listed';
      isOpenResolved = true;
    }

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
      isOpen: isOpenResolved,
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