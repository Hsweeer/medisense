import 'package:shared_preferences/shared_preferences.dart';

class NutritionHistoryPreferences {
  NutritionHistoryPreferences._();
  static final instance = NutritionHistoryPreferences._();

  static const _key = 'save_nutrition_history';

  Future<bool> isEnabled() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(_key) ?? true;
  }

  Future<void> setEnabled(bool enabled) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_key, enabled);
  }
}
