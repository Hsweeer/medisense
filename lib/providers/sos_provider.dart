import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../data/mock/mock_data.dart';
import '../data/models/models.dart';

enum SosPhase { idle, countdown, active }

/// Emergency ride lifecycle after "BOOK EMERGENCY RIDE".
enum RideStage { none, searching, assigned, pickedUp, arrived }

/// One-tap emergency flow: 5-second cancel window → active SOS with
/// hospital selection and a direct emergency-ride booking.
class SosProvider extends ChangeNotifier {
  SosProvider() {
    // Reset state whenever the user changes
    FirebaseAuth.instance.authStateChanges().listen((user) {
      debugPrint('[SosProvider] authStateChanged: ${user?.email}');
      cancel();
    });
  }

  SosPhase phase = SosPhase.idle;
  int countdown = 5;

  /// Nearest ER pre-selected; user can switch before or during the ride.
  Facility selectedHospital = MockData.hospitals
      .reduce((a, b) => a.distanceMiles <= b.distanceMiles ? a : b);

  bool notifyContacts = true;
  bool contactsNotified = false;

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

  void selectHospital(Facility hospital) {
    selectedHospital = hospital;
    notifyListeners();
  }

  void toggleNotifyContacts(bool value) {
    notifyContacts = value;
    contactsNotified = phase == SosPhase.active && value;
    notifyListeners();
  }

  /// Books the emergency ride and walks the mock trip through its stages.
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
