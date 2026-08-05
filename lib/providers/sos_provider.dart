import 'dart:async';
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
    FirebaseAuth.instance.authStateChanges().listen((user) {
      debugPrint('[SosProvider] authStateChanged: ${user?.email}');
      cancel();
    });
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
      final status = await FlutterOverlayWindow.isPermissionGranted();
      if (!status) {
        final granted = await FlutterOverlayWindow.requestPermission();
        if (granted == null || !granted) {
          showAccessibilityButton = false;
          notifyListeners();
          return;
        }
      }
      
      // Request Battery Exemption for background reliability
      try {
        const channel = MethodChannel('com.medisense.medisense_app/native_alarm');
        await channel.invokeMethod('requestIgnoreBatteryOptimizations');
      } catch (e) {}

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
    } else {
      await FlutterOverlayWindow.closeOverlay();
    }

    showAccessibilityButton = value;
    notifyListeners();
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
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _rideTimer?.cancel();
    super.dispose();
  }
}
