import 'dart:async';
import 'dart:io' show Platform;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:uuid/uuid.dart';

import '../core/services/facility_cache_service.dart';
import '../core/services/overpass_service.dart';
import '../core/services/routing_service.dart';
import '../core/services/sos_backend_service.dart';
import '../data/models/models.dart';

enum SosPhase {
  idle,
  countdown,
  active,
  cancelling,
  cancelled,
  resolved,
  failed,
}

class SosProvider extends ChangeNotifier {
  SosProvider() {
    _loadSettings();
    FirebaseAuth.instance.authStateChanges().listen((user) {
      _loadSettings();
    });
  }

  SosPhase phase = SosPhase.idle;
  int countdown = 5;

  LatLng? userLocation;
  List<Facility> nearbyHospitals = [];
  Facility? selectedHospital;
  bool isLoadingHospitals = false;
  bool isLocating = false;
  String? sosSessionId;
  String? trackingToken;
  String? errorMessage;

  List<LatLng> currentRoutePoints = [];
  double realEtaMinutes = 0;
  bool isCalculatingRoute = false;

  bool notifyContacts = true;
  bool contactsNotified = false;
  String contactNotificationStatus = 'pending';
  String trackingUrl = '';
  bool showAccessibilityButton = false;

  Timer? _timer;
  StreamSubscription<Position>? _positionSub;

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  Future<void> _loadSettings() async {
    final uid = _uid;
    if (uid == null) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      if (doc.exists) {
        showAccessibilityButton =
            doc.data()?['sosAccessibilityEnabled'] ?? false;
        if (showAccessibilityButton) {
          await _startOverlay();
        }
        notifyListeners();
      }
    } catch (e) {
      debugPrint('[SosProvider] _loadSettings error: $e');
    }
  }

  Future<void> trigger(
    LatLng? location,
    List<EmergencyContact> contacts,
  ) async {
    _timer?.cancel();
    userLocation = location;
    errorMessage = null;
    phase = SosPhase.countdown;
    countdown = 5;
    notifyListeners();

    _timer = Timer.periodic(const Duration(seconds: 1), (t) async {
      countdown--;
      if (countdown <= 0) {
        t.cancel();
        await _activateSos(contacts);
        return;
      }
      notifyListeners();
    });
  }

  Future<void> triggerImmediate(
    LatLng? location,
    List<EmergencyContact> contacts,
  ) async {
    _timer?.cancel();
    userLocation = location;
    errorMessage = null;
    await _activateSos(contacts);
  }

  /// Instant, cached last-known device position — no live GPS wait at
  /// all. Used as a fast starting point in [_activateSos] so hospital
  /// lookup and session creation can begin immediately instead of
  /// blocking on a fresh GPS lock, which can take many seconds indoors
  /// or with a weak signal. This is exactly why the Nearby screen feels
  /// fast (it starts from a cached position right away) while SOS felt
  /// slow (it was waiting for a brand-new fix before doing anything).
  /// [_startLiveTracking], started inside [_activateSos], naturally
  /// replaces this with a precise fix within moments regardless, so
  /// starting from a slightly stale cached position costs nothing in
  /// accuracy — it only saves the wait.
  Future<LatLng?> _resolveLastKnownLocation() async {
    try {
      final pos = await Geolocator.getLastKnownPosition();
      if (pos == null) return null;
      return LatLng(pos.latitude, pos.longitude);
    } catch (e) {
      debugPrint('[SosProvider] getLastKnownPosition error: $e');
      return null;
    }
  }

  Future<LatLng?> _resolveLiveLocation() async {
    isLocating = true;
    notifyListeners();

    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
        ),
      ).timeout(const Duration(seconds: 20));
      return LatLng(pos.latitude, pos.longitude);
    } catch (e) {
      debugPrint('[SosProvider] resolve live location error: $e');
      errorMessage =
          'Location unavailable right now. Please try again or call emergency services directly.';
      return null;
    } finally {
      isLocating = false;
      notifyListeners();
    }
  }

  Future<void> _activateSos(List<EmergencyContact> contacts) async {
    // Try the instant cached fix first — this is the main speed fix.
    // Previously, if `userLocation` was null here, the only option was a
    // full fresh GPS lock (up to 20s) before hospitals even started
    // loading. Now we grab whatever the OS already has cached (near-
    // instant) and use that to get moving immediately.
    userLocation ??= await _resolveLastKnownLocation();
    // Only wait for a real GPS lock if there's truly no cached fix at
    // all (e.g. first-ever launch, or location was just enabled).
    userLocation ??= await _resolveLiveLocation();

    if (userLocation == null) {
      phase = SosPhase.failed;
      errorMessage =
          'Unable to determine your current location. Please enable location access and try again.';
      notifyListeners();
      return;
    }

    phase = SosPhase.active;
    contactsNotified = false;
    trackingToken = const Uuid().v4();
    notifyListeners();

    await _fetchHospitals(userLocation!);
    await _createSosSession(contacts);
    _startLiveTracking();
  }

  void _startLiveTracking() {
    _positionSub?.cancel();
    _positionSub =
        Geolocator.getPositionStream(
          locationSettings: _liveTrackingSettings(),
        ).listen(
          (pos) {
            userLocation = LatLng(pos.latitude, pos.longitude);
            _updateSessionLocation(userLocation!);
            if (selectedHospital != null) {
              _calculateRoute(userLocation!, selectedHospital!.position);
            }
            notifyListeners();
          },
          onError: (Object e) {
            debugPrint('[SosProvider] live tracking error: $e');
          },
        );
  }

  /// Location settings used ONLY for the continuous stream while an SOS is
  /// ACTIVE. On Android this attaches a foreground-service notification
  /// (via geolocator's built-in support) so location updates keep flowing
  /// when the screen locks or the app is backgrounded during a real
  /// emergency — a plain stream alone can be throttled/killed by Android's
  /// background execution limits. This is intentionally NOT used for the
  /// app's general "nearby care" location updates (see LocationProvider),
  /// which don't need a persistent foreground service running at all times.
  LocationSettings _liveTrackingSettings() {
    if (Platform.isAndroid) {
      return AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
        intervalDuration: const Duration(seconds: 5),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'MediSense SOS is active',
          notificationText:
              'Sharing your live location with responders and emergency contacts.',
          notificationIcon: AndroidResource(
            name: 'ic_sos',
            defType: 'drawable',
          ),
          enableWakeLock: true,
          setOngoing: true,
        ),
      );
    }
    return const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10,
    );
  }

  Future<void> _updateSessionLocation(LatLng loc) async {
    if (sosSessionId == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('sos_sessions')
          .doc(sosSessionId)
          .update({
            'currentLocation': {'lat': loc.latitude, 'lng': loc.longitude},
            'locationUpdatedAt': FieldValue.serverTimestamp(),
            'locationAccuracy': 10,
          });
    } catch (e) {
      debugPrint('[SosProvider] location update error: $e');
    }

    // Also update the reduced-info tracking_sessions doc — this is the
    // ONLY document an emergency contact actually reads (see
    // firestore.rules), so without this update their tracking view would
    // stay frozen on the SOS start location forever.
    if (trackingToken != null) {
      try {
        await FirebaseFirestore.instance
            .collection('tracking_sessions')
            .doc(trackingToken)
            .update({
              'lastLocation': {'lat': loc.latitude, 'lng': loc.longitude},
              'lastLocationUpdatedAt': FieldValue.serverTimestamp(),
            });
      } catch (e) {
        debugPrint('[SosProvider] tracking session location update error: $e');
      }
    }
  }

  Future<void> _calculateRoute(LatLng start, LatLng end) async {
    isCalculatingRoute = true;
    notifyListeners();
    final route = await RoutingService.instance.getRoute(start, end);
    if (route != null) {
      currentRoutePoints = route.points;
      realEtaMinutes = route.durationMinutes;
    }
    isCalculatingRoute = false;
    notifyListeners();
  }

  Future<void> _fetchHospitals(LatLng location) async {
    isLoadingHospitals = true;
    notifyListeners();
    try {
      final results = await OverpassService.instance.fetchNearby(
        latitude: location.latitude,
        longitude: location.longitude,
        userPosition: location,
        radiusMeters: 10000,
        // SOS only ever uses hospital results — asking Overpass for
        // pharmacies too (the default for the Nearby screen) meant a
        // larger response and more parsing work on every single SOS
        // trigger for data that was thrown away immediately after.
        types: const {FacilityType.hospital},
      );

      nearbyHospitals = results;
      if (nearbyHospitals.isNotEmpty) {
        selectHospital(nearbyHospitals.first);
        // Cache this real, live result so a later SOS with no connectivity
        // still has real (if slightly stale) hospitals instead of nothing.
        unawaited(
          FacilityCacheService.instance.save(
            latitude: location.latitude,
            longitude: location.longitude,
            facilities: results,
          ),
        );
      } else {
        await _fallbackToCachedHospitals(location);
      }
    } catch (e) {
      debugPrint('[SosProvider] fetchHospitals error: $e');
      await _fallbackToCachedHospitals(location);
    } finally {
      isLoadingHospitals = false;
      notifyListeners();
    }
  }

  /// Falls back to previously cached REAL hospital data (from a prior
  /// successful live fetch near this location) when the live Overpass
  /// lookup fails or returns nothing. Never falls back to mock/seed data —
  /// if no real cache exists either, an honest error is shown instead.
  Future<void> _fallbackToCachedHospitals(LatLng location) async {
    final cached = await FacilityCacheService.instance.load(
      latitude: location.latitude,
      longitude: location.longitude,
    );
    final cachedHospitals =
        cached?.facilities
            .where((f) => f.type == FacilityType.hospital)
            .toList() ??
        [];

    if (cachedHospitals.isNotEmpty) {
      nearbyHospitals = cachedHospitals;
      selectHospital(cachedHospitals.first);
      errorMessage = null;
    } else {
      nearbyHospitals = [];
      errorMessage = 'Nearby hospitals unavailable right now.';
    }
  }

  Future<void> _createSosSession(List<EmergencyContact> contacts) async {
    final uid = _uid;
    if (uid == null || userLocation == null) return;

    try {
      final docRef = await FirebaseFirestore.instance
          .collection('sos_sessions')
          .add({
            'userId': uid,
            'status': 'active',
            'startedAt': FieldValue.serverTimestamp(),
            'trackingToken': trackingToken,
            'trackingUrl': 'medisense://sos/track?token=$trackingToken',
            'currentLocation': {
              'lat': userLocation!.latitude,
              'lng': userLocation!.longitude,
            },
            'locationAccuracy': 10,
            'locationUpdatedAt': FieldValue.serverTimestamp(),
            'selectedHospital': selectedHospital == null
                ? null
                : {
                    'name': selectedHospital!.name,
                    'lat': selectedHospital!.position.latitude,
                    'lng': selectedHospital!.position.longitude,
                  },
            'contacts': contacts
                .where((c) => c.phone.trim().isNotEmpty)
                .map(
                  (c) => {
                    'name': c.name,
                    'phone': c.phone,
                    'status': 'pending',
                  },
                )
                .toList(),
          });
      sosSessionId = docRef.id;
      trackingUrl = 'medisense://sos/track?token=$trackingToken';
      await _attemptContactNotifications(contacts);
      await FirebaseFirestore.instance
          .collection('tracking_sessions')
          .doc(trackingToken)
          .set({
            'sessionId': sosSessionId,
            'token': trackingToken,
            // Required so the security rules can verify the SOS owner on
            // create/update — see firestore.rules `tracking_sessions`.
            'userId': uid,
            'status': 'active',
            'createdAt': FieldValue.serverTimestamp(),
            'expiresAt': Timestamp.fromDate(
              DateTime.now().add(const Duration(hours: 12)),
            ),
            'lastLocation': {
              'lat': userLocation!.latitude,
              'lng': userLocation!.longitude,
            },
          }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[SosProvider] _createSosSession error: $e');
      phase = SosPhase.failed;
      errorMessage =
          'SOS session could not be created. Please try again or call emergency services.';
      notifyListeners();
    }
  }

  Future<void> _attemptContactNotifications(
    List<EmergencyContact> contacts,
  ) async {
    if (sosSessionId == null) return;

    final validContacts = contacts
        .where((c) => c.phone.trim().isNotEmpty)
        .toList();
    if (validContacts.isEmpty) {
      contactNotificationStatus = 'failed';
      contactsNotified = false;
      await FirebaseFirestore.instance
          .collection('sos_sessions')
          .doc(sosSessionId)
          .update({
            'contactNotificationStatus': 'failed',
            'contactsNotifiedAt': null,
            'contactsDeliverySummary':
                'No valid emergency contact numbers found.',
          });
      notifyListeners();
      return;
    }

    contactNotificationStatus = 'pending';
    contactsNotified = false;
    await FirebaseFirestore.instance
        .collection('sos_sessions')
        .doc(sosSessionId)
        .update({
          'contactNotificationStatus': 'pending',
          'contactsNotifiedAt': FieldValue.serverTimestamp(),
          'contactsDeliverySummary':
              'Notification attempts started for ${validContacts.length} contact(s).',
          'contacts': validContacts
              .map(
                (c) => {'name': c.name, 'phone': c.phone, 'status': 'pending'},
              )
              .toList(),
        });

    try {
      final result = await SosBackendService.instance.notifyContacts(
        sosSessionId: sosSessionId!,
        trackingToken: trackingToken ?? '',
        contacts: validContacts
            .map((c) => {'name': c.name, 'phone': c.phone})
            .toList(),
        userName: FirebaseAuth.instance.currentUser?.displayName ?? 'User',
      );

      final status = (result['status'] ?? 'pending').toString();
      contactNotificationStatus = status;
      contactsNotified = status == 'sent' || status == 'delivered';
      await FirebaseFirestore.instance
          .collection('sos_sessions')
          .doc(sosSessionId)
          .update({
            'contactNotificationStatus': status,
            'contactsNotifiedAt': status == 'sent' || status == 'delivered'
                ? FieldValue.serverTimestamp()
                : FieldValue.delete(),
            'contactsDeliverySummary':
                result['message'] ?? 'Emergency alerts sent to contacts.',
          });
    } catch (e) {
      debugPrint('[SosProvider] backend contact notification error: $e');
      contactNotificationStatus = 'failed';
      contactsNotified = false;
      await FirebaseFirestore.instance
          .collection('sos_sessions')
          .doc(sosSessionId)
          .update({
            'contactNotificationStatus': 'failed',
            'contactsDeliverySummary':
                'Emergency contact notifications could not be sent.',
          });
    }

    notifyListeners();
  }

  void selectHospital(Facility hospital) {
    selectedHospital = hospital;
    if (userLocation != null) {
      _calculateRoute(userLocation!, hospital.position);
    }
    if (sosSessionId != null) {
      FirebaseFirestore.instance
          .collection('sos_sessions')
          .doc(sosSessionId)
          .update({
            'selectedHospital': {
              'name': hospital.name,
              'lat': hospital.position.latitude,
              'lng': hospital.position.longitude,
            },
          })
          .catchError((e) {
            debugPrint('[SosProvider] update selected hospital error: $e');
          });
    }
    notifyListeners();
  }

  Future<void> resolve() async {
    _timer?.cancel();
    _positionSub?.cancel();

    if (sosSessionId != null) {
      try {
        await FirebaseFirestore.instance
            .collection('sos_sessions')
            .doc(sosSessionId)
            .update({
              'status': 'resolved',
              'resolvedAt': FieldValue.serverTimestamp(),
              'contactNotificationStatus': 'resolved',
            });
      } catch (e) {
        debugPrint('[SosProvider] resolve session update error: $e');
      }
      if (trackingToken != null) {
        // Same backend-first, direct-write-fallback pattern as cancel().
        final backendResult = await SosBackendService.instance
            .updateTrackingStatus(
              trackingToken: trackingToken!,
              status: 'resolved',
              accessRestricted: true,
            );
        if (backendResult['status'] == 'failed') {
          try {
            await FirebaseFirestore.instance
                .collection('tracking_sessions')
                .doc(trackingToken)
                .update({
                  'status': 'resolved',
                  'endedAt': FieldValue.serverTimestamp(),
                  'accessRestricted': true,
                });
          } catch (e) {
            debugPrint('[SosProvider] resolve tracking fallback error: $e');
          }
        }
      }
    }

    phase = SosPhase.resolved;
    sosSessionId = null;
    trackingToken = null;
    trackingUrl = '';
    currentRoutePoints = [];
    realEtaMinutes = 0;
    notifyListeners();
  }

  Future<void> cancel() async {
    _timer?.cancel();
    _positionSub?.cancel();

    // Reflect the cancellation-in-progress state immediately so any UI
    // watching `phase` (not just the screen that called this) shows a
    // "cancelling" state instead of still looking active while the
    // Firestore/backend calls below are in flight.
    final hadActiveSession = sosSessionId != null;
    if (hadActiveSession) {
      phase = SosPhase.cancelling;
      notifyListeners();
    }

    if (sosSessionId != null) {
      try {
        await FirebaseFirestore.instance
            .collection('sos_sessions')
            .doc(sosSessionId)
            .update({
              'status': 'cancelled',
              'cancelledAt': FieldValue.serverTimestamp(),
              'endedAt': FieldValue.serverTimestamp(),
              'contactNotificationStatus': 'cancelled',
            });
      } catch (e) {
        debugPrint('[SosProvider] cancel session update error: $e');
      }
      if (trackingToken != null) {
        // Prefer the secure backend to invalidate the tracking session;
        // fall back to the direct Firestore write only if the backend
        // call fails, so cancellation never silently leaves tracking
        // open just because the Cloud Function was unreachable.
        final backendResult = await SosBackendService.instance
            .updateTrackingStatus(
              trackingToken: trackingToken!,
              status: 'cancelled',
              accessRestricted: true,
            );
        if (backendResult['status'] == 'failed') {
          try {
            await FirebaseFirestore.instance
                .collection('tracking_sessions')
                .doc(trackingToken)
                .update({
                  'status': 'cancelled',
                  'endedAt': FieldValue.serverTimestamp(),
                  'accessRestricted': true,
                });
          } catch (e) {
            debugPrint('[SosProvider] cancel tracking fallback error: $e');
          }
        }
      }
    }

    phase = hadActiveSession ? SosPhase.cancelled : SosPhase.idle;
    sosSessionId = null;
    trackingToken = null;
    trackingUrl = '';
    userLocation = null;
    nearbyHospitals = [];
    selectedHospital = null;
    currentRoutePoints = [];
    realEtaMinutes = 0;
    errorMessage = null;
    contactsNotified = false;
    contactNotificationStatus = 'pending';
    notifyListeners();
  }

  /// Resets an ended (cancelled/resolved/failed) session back to idle so
  /// the next SOS trigger starts clean. Call this when leaving the SOS
  /// screen after cancellation/resolution rather than assuming `cancel()`
  /// itself should leave `phase` at `idle`.
  void acknowledgeEnded() {
    if (phase == SosPhase.cancelled ||
        phase == SosPhase.resolved ||
        phase == SosPhase.failed) {
      phase = SosPhase.idle;
      notifyListeners();
    }
  }

  void toggleNotifyContacts(bool value) {
    notifyContacts = value;
    notifyListeners();
  }

  Future<void> _persistSettings(bool value) async {
    final uid = _uid;
    if (uid == null) return;
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'sosAccessibilityEnabled': value,
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[SosProvider] _persistSettings error: $e');
    }
  }

  Future<void> _startOverlay() async {
    if (!await FlutterOverlayWindow.isActive()) {
      await FlutterOverlayWindow.showOverlay(
        enableDrag: true,
        overlayTitle: 'SOS Button',
        overlayContent: 'MediSense Emergency Button',
        flag: OverlayFlag.defaultFlag,
        visibility: NotificationVisibility.visibilityPublic,
        height: 160,
        width: 160,
      );
    }
  }

  Future<void> toggleAccessibilityButton(bool value) async {
    if (value) {
      final status = await FlutterOverlayWindow.isPermissionGranted();
      if (!status) {
        await FlutterOverlayWindow.requestPermission();
        return;
      }
      showAccessibilityButton = true;
      await _startOverlay();
    } else {
      showAccessibilityButton = false;
      await FlutterOverlayWindow.closeOverlay();
    }
    await _persistSettings(showAccessibilityButton);
    notifyListeners();
  }
}
