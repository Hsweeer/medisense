import 'package:shared_preferences/shared_preferences.dart';

import 'alarm_sound_catalog.dart';

/// Persists the app-wide alarm sound selected in Settings.
class AlarmSoundPrefs {
  AlarmSoundPrefs._();

  static final AlarmSoundPrefs instance = AlarmSoundPrefs._();
  static const _key = 'medisense_selected_alarm_sound_id';

  Future<AlarmSoundOption> getSelected() async {
    final prefs = await SharedPreferences.getInstance();
    final savedId = prefs.getString(_key);
    return kAlarmSounds.firstWhere(
      (option) => option.id == savedId,
      orElse: () => kSystemDefaultSound,
    );
  }

  Future<void> setSelected(AlarmSoundOption option) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, option.id);
  }
}
