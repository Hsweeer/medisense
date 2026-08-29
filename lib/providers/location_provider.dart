import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';

import '../core/services/location_service.dart';

export '../core/services/location_service.dart' show LocationAccess;

enum LocationLoadState { initial, loading, ready, error }

/// App-wide source of truth for the user's real device location.
///
/// Screens that need "near me" behavior watch this instead of touching
/// `geolocator` directly. It exposes:
/// - [access] — the permission/service state, so UI can show the right
///   prompt (ask / open settings / etc.) instead of failing silently.
/// - [position] — the last known real GPS fix, or null if we don't have one.
/// - [positionOrFallback] — safe value to hand to a map that always needs
///   *some* coordinate to center on.
/// - [label] — human-readable "City, ST" for display, e.g. on the home
///   screen greeting.
class LocationProvider extends ChangeNotifier {
  LocationAccess _access = LocationAccess.denied;
  LocationLoadState _state = LocationLoadState.initial;
  LatLng? _position;
  String? _label;
  String? _countryCode;
  bool _requestInFlight = false;
  StreamSubscription<Position>? _posSub;

  LocationAccess get access => _access;
  LocationLoadState get state => _state;
  LatLng? get position => _position;
  String? get label => _label;

  /// ISO country code (e.g. "US", "PK") derived from the user's real GPS
  /// position via reverse geocoding. Null until resolved or if it's
  /// unavailable — callers (e.g. emergency-number lookup) must handle that
  /// by falling back to a sane default rather than assuming a country.
  String? get countryCode => _countryCode;

  bool get isGranted => _access == LocationAccess.granted;
  bool get isLoading => _state == LocationLoadState.loading;

  /// Real position when we have one. Screens must handle null by showing an
  /// explicit error state instead of silently falling back to any fake GPS.
  LatLng? get positionOrFallback => _position;

  /// What to show next to a pin/greeting while we figure things out.
  String get displayLabel {
    if (_state == LocationLoadState.loading) return 'Locating…';
    if (isGranted && _label != null) return _label!;
    if (isGranted && _position != null) return 'Current location';
    if (_access == LocationAccess.serviceDisabled) return 'Location services off';
    return 'Location off · tap to enable';
  }

  /// Prompts the native permission dialog.
  ///
  /// [silent] should be true ONLY for the automatic call made once when
  /// the patient shell first loads (see [LocationService.requestAccess]
  /// for why) — every explicit user action, like tapping "enable
  /// location", must call this with [silent] false so a prior denial
  /// doesn't permanently prevent retrying.
  Future<void> requestAccess({bool silent = false}) async {
    if (_requestInFlight) return;
    _requestInFlight = true;
    _state = LocationLoadState.loading;
    notifyListeners();

    try {
      final access = await LocationService.instance.requestAccess(silent: silent);
      _access = access;
      if (access == LocationAccess.granted) {
        await _loadPosition();
      } else {
        _state = LocationLoadState.error;
      }
    } catch (_) {
      _state = LocationLoadState.error;
    } finally {
      _requestInFlight = false;
      notifyListeners();
    }
  }

  /// Re-reads permission status without prompting — cheap, safe to call
  /// from `didChangeAppLifecycleState` when the user comes back from
  /// Settings after enabling location.
  Future<void> refreshAccessSilently() async {
    final access = await LocationService.instance.currentAccess();
    if (access == _access) return;
    _access = access;
    if (access == LocationAccess.granted && _position == null) {
      await _loadPosition();
    }
    notifyListeners();
  }

  /// Force a fresh GPS fix (e.g. user tapped a "recenter" button).
  Future<void> refreshPosition() async {
    if (!isGranted) return;
    _state = LocationLoadState.loading;
    notifyListeners();
    await _loadPosition();
    notifyListeners();
  }

  Future<void> _loadPosition() async {
    try {
      final pos = await LocationService.instance.currentPosition();
      _position = LatLng(pos.latitude, pos.longitude);
      _state = LocationLoadState.ready;

      // Start a position stream so nearby searches update as the user moves.
      _posSub?.cancel();
      _posSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
        ),
      ).listen((p) {
        _position = LatLng(p.latitude, p.longitude);
        _state = LocationLoadState.ready;
        notifyListeners();
      }, onError: (_) {
        // Ignore stream errors — keep last known position.
      });

      // Reverse geocoding is best-effort — never block the position update on it.
      unawaited(_loadLabel());
    } catch (_) {
      _state = LocationLoadState.error;
    }
  }

  Future<void> _loadLabel() async {
    final pos = _position;
    if (pos == null) return;
    final info =
    await LocationService.instance.placeInfoFor(pos.latitude, pos.longitude);
    if (info.label == null && info.countryCode == null) return;
    _label = info.label ?? _label;
    _countryCode = info.countryCode ?? _countryCode;
    notifyListeners();
  }

  Future<void> openSettings() {
    return _access == LocationAccess.serviceDisabled
        ? LocationService.instance.openLocationSettings()
        : LocationService.instance.openAppSettings();
  }

  @override
  void dispose() {
    _posSub?.cancel();
    super.dispose();
  }
}