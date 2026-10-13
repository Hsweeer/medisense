// lib/core/services/overpass_service.dart

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../../data/models/models.dart';

class OverpassAllEndpointsFailedException implements Exception {
  @override
  String toString() =>
      'All Overpass endpoints failed or timed out. This usually means the '
          'device\'s current network cannot reach any of the free OSM mirrors '
          '(e.g. a carrier/firewall blocking them), rather than the app itself '
          'being broken — try a different network (Wi-Fi vs mobile data) if '
          'this keeps happening.';
}

/// Result of racing every mirror for one [FacilityType]'s query — carries
/// whether that specific type's fetch failed outright, so [fetchNearby]
/// can tell "this type failed" apart from "this type genuinely has zero
/// results nearby" and only raise [OverpassAllEndpointsFailedException]
/// when every requested type failed.
class _TypeFetchResult {
  const _TypeFetchResult(this.facilities, {required this.failed});
  final List<Facility> facilities;
  final bool failed;
}

/// Public result of [OverpassService.fetchNearby] — facilities plus which
/// types failed to load so the UI can show an honest partial-failure note
/// (e.g. hospitals OK, pharmacies timed out).
class NearbyFacilitiesResult {
  const NearbyFacilitiesResult({
    required this.facilities,
    this.hospitalFailed = false,
    this.pharmacyFailed = false,
  });

  final List<Facility> facilities;
  final bool hospitalFailed;
  final bool pharmacyFailed;

  bool get anyPartialFailure => hospitalFailed || pharmacyFailed;
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
      var endMin = int.parse(match.group(3)!) * 60 + int.parse(match.group(4)!);
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
      dotenv.env['OVERPASS_ENDPOINT_FALLBACK_3'],
      dotenv.env['OVERPASS_ENDPOINT_FALLBACK_4'],
    ].whereType<String>().where((e) => e.trim().isNotEmpty).toList();

    if (fromEnv.isNotEmpty) return fromEnv;

    // Safety net — same defaults as before, used only if .env is missing
    // or these specific keys weren't set.
    //
    // Expanded from 3 to 5 mirrors: field reports showed all three
    // original mirrors (overpass-api.de, kumi.systems, private.coffee)
    // timing out together even after fetchNearby started racing them in
    // parallel — meaning the bottleneck isn't sequential-vs-parallel
    // timing anymore, it's that all three happened to be
    // slow/unreachable from that network at once (common with these
    // small free community mirrors, especially over some South Asian
    // ISPs/mobile carriers). Racing more independent mirrors at once
    // costs nothing extra in wait time (they all run concurrently, still
    // capped by the same _requestTimeout) but meaningfully raises the
    // odds that at least one responds.
    //
    // overpass.osm.ch removed: field logs showed it consistently
    // returning an HTML/XML error page instead of JSON on every single
    // attempt (FormatException: "Unexpected character" parsing "<?xml
    // ...") — this mirror doesn't actually serve this app's [out:json]
    // requests at all, so keeping it in the race just burns a request
    // slot for a guaranteed failure.
    //
    // maps.mail.ru tried as a fifth mirror and then removed again: field
    // logs showed it both timing out AND, on some attempts, throwing an
    // unhandled `HandshakeException: CERTIFICATE_VERIFY_FAILED: Hostname
    // mismatch` — its TLS certificate doesn't actually match the
    // hostname being connected to for this path, which is a server-side
    // misconfiguration on their end, not something fixable from here.
    // Worse, that specific exception type escaped the per-endpoint
    // catchError below (it surfaces from the underlying socket outside
    // the awaited request chain), showing up as raw "Unhandled
    // Exception" noise in the app's logs. Back to 4 mirrors that have
    // actually proven reliable rather than chasing a fifth.
    return const [
      'https://overpass-api.de/api/interpreter',
      'https://overpass.kumi.systems/api/interpreter',
      'https://overpass.private.coffee/api/interpreter',
      'https://overpass.openstreetmap.fr/api/interpreter',
    ];
  }

  // BUG FIX: this was previously 10s while the query below tells the
  // Overpass server itself to keep trying for up to 25s ([timeout:25]).
  // That mismatch meant the client was aborting requests before the
  // server's own stated budget was even used up — exactly what was
  // showing up in the field as "all three endpoints time out" every
  // single time, especially over slower/longer network paths (e.g. a
  // request routed to a European Overpass mirror from South Asia), where
  // 10-18s for a combined hospital+pharmacy regex query is completely
  // normal, not a sign the endpoint is actually down. The client should
  // never give up sooner than the timeout it told the server to honor —
  // 22s here gives the query's own 20s server-side budget (see
  // _buildQuery) a full, fair chance plus a small margin for network
  // round-trip.
  static const _requestTimeout = Duration(seconds: 22);

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

  Future<NearbyFacilitiesResult> fetchNearby({
    required double latitude,
    required double longitude,
    required LatLng userPosition,
    double radiusMeters = 5000,
    /// Pharmacies use a wider search by default — local chemist shops are
    /// mapped more sparsely than hospitals on OSM in South Asia.
    double pharmacyRadiusMeters = 10000,
    // Which facility types to actually query for. Defaults to both.
    // SOS passes {FacilityType.hospital} only.
    Set<FacilityType> types = const {
      FacilityType.hospital,
      FacilityType.pharmacy,
    },
  }) async {
    // Each type gets its OWN Overpass request so a heavy pharmacy query
    // cannot starve the hospital query (or vice versa).
    final typeList = types.toList();
    final results = await Future.wait(
      typeList.map(
            (type) => _fetchOneType(
          type: type,
          radiusMeters: type == FacilityType.pharmacy
              ? pharmacyRadiusMeters
              : radiusMeters,
          latitude: latitude,
          longitude: longitude,
          userPosition: userPosition,
        ),
      ),
    );

    if (results.every((r) => r.failed) && results.isNotEmpty) {
      throw OverpassAllEndpointsFailedException();
    }

    bool hospitalFailed = false;
    bool pharmacyFailed = false;
    final facilities = <Facility>[];
    for (var i = 0; i < typeList.length; i++) {
      final type = typeList[i];
      final r = results[i];
      if (r.failed) {
        if (type == FacilityType.hospital) hospitalFailed = true;
        if (type == FacilityType.pharmacy) pharmacyFailed = true;
        debugPrint(
          '[OverpassService] ${type.name} fetch failed after retries '
              '(showing other types if available)',
        );
      } else {
        facilities.addAll(r.facilities);
      }
    }

    debugPrint(
      '[OverpassService] total facilities: ${facilities.length} '
          '(hospitalFailed=$hospitalFailed pharmacyFailed=$pharmacyFailed)',
    );

    return NearbyFacilitiesResult(
      facilities: facilities,
      hospitalFailed: hospitalFailed,
      pharmacyFailed: pharmacyFailed,
    );
  }

  /// Races every configured mirror for a single facility [type]'s query —
  /// same racing strategy as before, just scoped to one type so a heavy
  /// pharmacy query can't eat into a fast hospital query's shared budget.
  ///
  /// Automatically retries the whole race up to [_maxAutoRetries] times
  /// (short delay between attempts) before giving up. Field logs showed
  /// the dominant failure modes here are *transient*, not structural —
  /// overpass-api.de returning 429 (rate limited) or 504 (gateway
  /// timeout) because it's a shared, heavily-used free public server —
  /// and a moment later the exact same request often succeeds. Without
  /// this, a transient rate-limit meant the whole screen came back empty
  /// and the person had to notice and manually tap refresh themselves;
  /// this now absorbs that automatically, so a manual retry is only ever
  /// needed if the network is *persistently* unreachable.
  Future<_TypeFetchResult> _fetchOneType({
    required FacilityType type,
    required double radiusMeters,
    required double latitude,
    required double longitude,
    required LatLng userPosition,
  }) async {
    final maxRetries = type == FacilityType.pharmacy
        ? _pharmacyMaxAutoRetries
        : _maxAutoRetries;
    for (var attempt = 0; attempt <= maxRetries; attempt++) {
      final result = await _fetchOneTypeOnce(
        type: type,
        radiusMeters: radiusMeters,
        latitude: latitude,
        longitude: longitude,
        userPosition: userPosition,
      );
      if (!result.failed) return result;
      if (attempt < maxRetries) {
        await Future.delayed(_autoRetryDelay);
      }
    }
    return const _TypeFetchResult([], failed: true);
  }

  static const _maxAutoRetries = 2;
  static const _pharmacyMaxAutoRetries = 3;
  static const _autoRetryDelay = Duration(seconds: 2);

  Future<_TypeFetchResult> _fetchOneTypeOnce({
    required FacilityType type,
    required double radiusMeters,
    required double latitude,
    required double longitude,
    required LatLng userPosition,
  }) async {
    final query = _buildQuery(
      radiusMeters: radiusMeters,
      latitude: latitude,
      longitude: longitude,
      types: {type},
    );

    // BUG FIX: this used to try each endpoint one after another — a
    // full 22s timeout on the first mirror, THEN 22s on the second,
    // THEN 22s on the third, meaning the worst case (all three mirrors
    // slow/overloaded, which is common for these free public Overpass
    // instances — overpass-api.de in particular is a shared, often-
    // overloaded free server) was up to ~66 seconds of waiting before
    // the caller ever saw a result or an error. Since only ONE endpoint
    // succeeding is actually needed, racing all three at once instead
    // means: a fast endpoint's response is used immediately without
    // waiting on the other two at all, and even the worst case (all
    // three genuinely dead) drops to a single ~22s window instead of
    // three stacked ones.
    final completer = Completer<List<Facility>>();
    final endpoints = _endpoints;
    var remaining = endpoints.length;

    for (final endpoint in endpoints) {
      unawaited(
        _attemptEndpoint(endpoint, query, userPosition)
            .then((facilities) {
          if (!completer.isCompleted) {
            completer.complete(facilities);
          }
        })
            .catchError((Object e) {
          remaining--;
          if (remaining == 0 && !completer.isCompleted) {
            completer.completeError(OverpassAllEndpointsFailedException());
          }
        }),
      );
    }

    try {
      return _TypeFetchResult(await completer.future, failed: false);
    } catch (_) {
      return const _TypeFetchResult([], failed: true);
    }
  }

  Future<List<Facility>> _attemptEndpoint(
      String endpoint,
      String query,
      LatLng userPosition,
      ) async {
    try {
      final response = await http
          .post(
        Uri.parse(endpoint),
        headers: {'User-Agent': _userAgent, 'Accept': 'application/json'},
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
            '${response.body.length > 200 ? response.body.substring(0, 200) : response.body}',
      );
      throw Exception('HTTP ${response.statusCode}');
    } catch (e) {
      debugPrint('[OverpassService] $endpoint threw: $e');
      rethrow;
    }
  }

  String _buildQuery({
    required double radiusMeters,
    required double latitude,
    required double longitude,
    required Set<FacilityType> types,
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
    final around = '(around:$radiusMeters,$latitude,$longitude)';
    final clauses = StringBuffer();

    if (types.contains(FacilityType.hospital)) {
      clauses.writeln('  node["amenity"~"^(hospital)\$",i]$around;');
      clauses.writeln('  way["amenity"~"^(hospital)\$",i]$around;');
      clauses.writeln('  relation["amenity"~"^(hospital)\$",i]$around;');
    }
    if (types.contains(FacilityType.pharmacy)) {
      // South Asian medical stores are tagged inconsistently on OSM —
      // catch the common real-world variants, not only amenity=pharmacy.
      clauses.writeln('  node["amenity"~"^(pharmacy|chemist)\$",i]$around;');
      clauses.writeln('  way["amenity"~"^(pharmacy|chemist)\$",i]$around;');
      clauses.writeln('  relation["amenity"~"^(pharmacy|chemist)\$",i]$around;');
      clauses.writeln(
        '  node["shop"~"^(chemist|pharmacy|drugstore|medical_supply)\$",i]$around;',
      );
      clauses.writeln(
        '  way["shop"~"^(chemist|pharmacy|drugstore|medical_supply)\$",i]$around;',
      );
      clauses.writeln(
        '  relation["shop"~"^(chemist|pharmacy|drugstore|medical_supply)\$",i]$around;',
      );
      clauses.writeln('  node["healthcare"~"^pharmacy\$",i]$around;');
      clauses.writeln('  way["healthcare"~"^pharmacy\$",i]$around;');
      clauses.writeln('  relation["healthcare"~"^pharmacy\$",i]$around;');
    }

    // Pharmacy queries are heavier (more clauses) — give them a slightly
    // larger server-side budget so mirrors are less likely to truncate.
    final timeout = types.contains(FacilityType.pharmacy) &&
        !types.contains(FacilityType.hospital)
        ? 25
        : 20;
    return '[out:json][timeout:$timeout];\n(\n$clauses);\nout center;\n';
  }

  List<Facility> _parseResponse(String body, LatLng userPosition) {
    final decoded = jsonDecode(body) as Map<String, dynamic>;
    final elements = (decoded['elements'] as List?) ?? const [];

    // Overpass returns HTTP 200 even when it hit its own internal
    // [timeout:N] budget partway through — it just adds a "remark"
    // describing that instead of erroring, and includes whatever partial
    // data it had gathered before cutting off. That previously looked
    // identical to "this query genuinely found nothing" from here. Now
    // that each facility type is its own request (see fetchNearby), this
    // should be rarer, but logging it means a truncated result is visible
    // in the field instead of silently read as "zero nearby".
    final remark = decoded['remark'] as String?;
    if (remark != null && remark.trim().isNotEmpty) {
      debugPrint('[OverpassService] server remark (possible partial/truncated result): $remark');
    }

    final facilities = <Facility>[];
    for (final raw in elements) {
      final facility = _fromOverpassElement(
        raw as Map<String, dynamic>,
        userPosition,
      );
      if (facility != null) facilities.add(facility);
    }

    final hospitalCount = facilities
        .where((f) => f.type == FacilityType.hospital)
        .length;
    final pharmacyCount = facilities
        .where((f) => f.type == FacilityType.pharmacy)
        .length;
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
        amenity == 'chemist' ||
        shop == 'chemist' ||
        shop == 'pharmacy' ||
        shop == 'drugstore' ||
        shop == 'medical_supply' ||
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
    // Same Open / Closed rules for hospitals AND pharmacies.
    if (openingHours != null && openingHours.trim().toLowerCase() == '24/7') {
      openLabel = 'Open';
      isOpenResolved = true;
    } else if (openNow == true) {
      openLabel = 'Open';
      isOpenResolved = true;
    } else if (openNow == false) {
      openLabel = 'Closed';
      isOpenResolved = false;
    } else if (type == FacilityType.hospital) {
      // Most hospitals run emergency care around the clock even when
      // opening_hours is missing on OSM.
      openLabel = 'Open';
      isOpenResolved = true;
    } else {
      // Pharmacy with no hours tagged — soft assumption from typical hours.
      final hour = DateTime.now().hour;
      if (hour >= 8 && hour < 22) {
        openLabel = 'Open';
        isOpenResolved = true;
      } else {
        openLabel = 'Closed';
        isOpenResolved = false;
      }
    }

    // OSM stores phone under several keys; collect the first non-empty one.
    String phone = '';
    for (final key in [
      'phone',
      'contact:phone',
      'contact:mobile',
      'mobile',
      'contact:whatsapp',
      'telephone',
    ]) {
      final v = tags[key];
      if (v == null) continue;
      final s = v.toString().trim();
      if (s.isNotEmpty) {
        phone = s;
        break;
      }
    }

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