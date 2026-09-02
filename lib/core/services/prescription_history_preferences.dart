import 'package:shared_preferences/shared_preferences.dart';

class PrescriptionHistoryPreferences {
  PrescriptionHistoryPreferences._();
  static final instance = PrescriptionHistoryPreferences._();

  static const _key = 'save_prescription_history';

  Future<bool> isEnabled() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(_key) ?? true;
  }

  Future<void> setEnabled(bool enabled) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_key, enabled);
  }
}