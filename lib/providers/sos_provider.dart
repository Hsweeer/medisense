import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../data/mock/mock_data.dart';
import '../data/models/models.dart';

enum SosPhase { idle, countdown, active }
enum RideStage { none, searching, assigned, pickedUp, arrived }

class SosProvider extends ChangeNotifier {
  SosProvider() {
    _init();
    FirebaseAuth.instance.authStateChanges().listen((user) {
      debugPrint('[SosProvider] authStateChanged: ${user?.email}');
      _init();
    });
  }

  void _init() async {
    cancel();
    await _loadSettings();
  }

  SosPhase phase = SosPhase.idle;
  int countdown = 5;

  Facility selectedHospital = MockData.hospitals
      .reduce((a, b) => a.distanceMiles <= b.distanceMiles ? a : b);

  bool notifyContacts = true;
  bool contactsNotified = false;
  bool showAccessibilityButton = false;

  RideStage stage = RideStage.none;
  int driverEtaMinutes = 6;

  Timer? _timer;
  Timer? _rideTimer;

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  Future<void> _loadSettings() async {
    final uid = _uid;
    if (uid == null) return;

    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (doc.exists) {
        final data = doc.data();
        showAccessibilityButton = data?['sosAccessibilityEnabled'] ?? false;
        if (showAccessibilityButton) {
          _startOverlay();
        }
        notifyListeners();
      }
    } catch (e) {
      debugPrint('[SosProvider] _loadSettings error: $e');
    }
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

  void trigger() {
    phase = SosPhase.countdown;
    countdown = 5;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      countdown--;
      if (countdown <= 0) {
        t.cancel();
        phase = SosPhase.active;
        contactsNotified = notifyContacts;
      }
      notifyListeners();
    });
    notifyListeners();
  }

  void triggerImmediate() {
    _timer?.cancel();
    phase = SosPhase.active;
    contactsNotified = notifyContacts;
    notifyListeners();
  }

  void selectHospital(Facility hospital) {
    selectedHospital = hospital;
    notifyListeners();
  }

  void toggleNotifyContacts(bool value) {
    notifyContacts = value;
    contactsNotified = phase == SosPhase.active && value;
    notifyListeners();
  }

  void toggleAccessibilityButton(bool value) async {
    if (value) {
      // 1. Check permission first
      final status = await FlutterOverlayWindow.isPermissionGranted();
      if (!status) {
        // If no permission, request it but DON'T turn on the toggle yet
        debugPrint('[SosProvider] Permission missing, requesting...');
        await FlutterOverlayWindow.requestPermission();
        // Keep toggle OFF
        showAccessibilityButton = false;
        notifyListeners();
        return;
      }

      // 2. Permission exists, now we can turn it on
      showAccessibilityButton = true;
      notifyListeners();

      try {
        const channel = MethodChannel('medisense_native_channel');
        await channel.invokeMethod('requestIgnoreBatteryOptimizations');
      } catch (e) {}

      await _startOverlay();
    } else {
      // Turn off
      showAccessibilityButton = false;
      notifyListeners();
      await FlutterOverlayWindow.closeOverlay();
    }

    // 3. Persist to cloud
    _persistSettings(showAccessibilityButton);
  }

  Future<void> _startOverlay() async {
    if (!await FlutterOverlayWindow.isActive()) {
      await FlutterOverlayWindow.showOverlay(
        enableDrag: true,
        overlayTitle: "SOS Button",
        overlayContent: "MediSense Emergency Button",
        flag: OverlayFlag.defaultFlag,
        visibility: NotificationVisibility.visibilityPublic,
        height: 160,
        width: 160,
      );
    }
  }

  void bookRide() {
    stage = RideStage.searching;
    driverEtaMinutes = selectedHospital.etaMinutes;
    notifyListeners();
    _rideTimer?.cancel();
    var tick = 0;
    _rideTimer = Timer.periodic(const Duration(seconds: 3), (t) {
      tick++;
      if (tick == 1) {
        stage = RideStage.assigned;
      } else if (tick <= 3) {
        driverEtaMinutes = (driverEtaMinutes - 2).clamp(1, 99);
      } else if (tick == 4) {
        stage = RideStage.pickedUp;
      } else {
        stage = RideStage.arrived;
        t.cancel();
      }
      notifyListeners();
    });
  }

  void cancelRide() {
    _rideTimer?.cancel();
    stage = RideStage.none;
    notifyListeners();
  }

  void cancel() {
    _timer?.cancel();
    _rideTimer?.cancel();
    phase = SosPhase.idle;
    stage = RideStage.none;
    countdown = 5;
    contactsNotified = false;
    if (FirebaseAuth.instance.currentUser == null) {
      showAccessibilityButton = false;
      FlutterOverlayWindow.closeOverlay();
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _rideTimer?.cancel();
    super.dispose();
  }
}
