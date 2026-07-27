import 'package:flutter/foundation.dart';

class AuthProvider extends ChangeNotifier {
  String phone = '';
  bool loggedIn = false;

  void setPhone(String value) {
    phone = value;
    notifyListeners();
  }

  void verify() {
    loggedIn = true;
    notifyListeners();
  }

  void logout() {
    loggedIn = false;
    phone = '';
    notifyListeners();
  }
}
