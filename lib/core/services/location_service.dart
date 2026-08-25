// lib/core/services/location_service.dart

import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The possible states of the device location service and app permission.
enum LocationAccess { granted, denied, deniedForever, serviceDisabled }

/// Small wrapper around the platform location APIs.
///
/// Keeping permission handling here ensures the app only asks the system once:
/// after a denial we merely report the state, and after a permanent denial we
/// direct the user to Settings instead of attempting another request.
class LocationService {
  LocationService._();

  static final instance = LocationService._();
  static const _hasPromptedKey = 'location_permission_prompted';

  Future<LocationAccess> currentAccess() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return LocationAccess.serviceDisabled;
    }
    return _fromPermission(await Geolocator.checkPermission());
  }

  /// [silent] is true only for the automatic prompt fired once when the
  /// app shell first loads — it's gated behind [_hasPromptedKey] so that
  /// auto-trigger never nags the user with the system dialog on every
  /// app open/login. An explicit user action (tapping "enable location")
  /// always passes silent: false and must be allowed to try again even
  /// after an earlier denial — the OS itself already refuses to show the
  /// dialog once permission is `deniedForever`, so there's no risk of
  /// nagging there; only our own flag was wrongly blocking the retry.
  Future<LocationAccess> requestAccess({bool silent = false}) async {
    final access = await currentAccess();
    if (access != LocationAccess.denied) return access;

    if (silent) {
      final preferences = await SharedPreferences.getInstance();
      if (preferences.getBool(_hasPromptedKey) ?? false) {
        return LocationAccess.denied;
      }
      // Record this before opening the system dialog. This keeps the
      // *automatic* shell-load prompt from firing again at next launch.
      await preferences.setBool(_hasPromptedKey, true);
    }

    return _fromPermission(await Geolocator.requestPermission());
  }

  Future<Position> currentPosition() {
    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      ),
    ).timeout(const Duration(seconds: 20));
  }

  Future<String?> labelFor(double latitude, double longitude) async {
    try {
      final places = await placemarkFromCoordinates(latitude, longitude);
      if (places.isEmpty) return null;
      final place = places.first;
      final city = place.locality?.trim().isNotEmpty == true
          ? place.locality!.trim()
          : place.subAdministrativeArea?.trim();
      final region = place.administrativeArea?.trim();
      return [city, region]
          .whereType<String>()
          .where((part) => part.isNotEmpty)
          .join(', ');
    } catch (_) {
      return null;
    }
  }

  Future<bool> openLocationSettings() => Geolocator.openLocationSettings();

  Future<bool> openAppSettings() => Geolocator.openAppSettings();

  LocationAccess _fromPermission(LocationPermission permission) {
    return switch (permission) {
      LocationPermission.always || LocationPermission.whileInUse =>
      LocationAccess.granted,
      LocationPermission.deniedForever => LocationAccess.deniedForever,
      LocationPermission.denied || LocationPermission.unableToDetermine =>
      LocationAccess.denied,
    };
  }
}