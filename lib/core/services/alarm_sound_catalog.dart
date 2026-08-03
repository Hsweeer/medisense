/// An alarm sound shared by the preview player and the native alarm code.
///
/// [id] is a lowercase Android raw-resource name. Every custom sound uses
/// the same filename in `assets/sounds`, Android `res/raw`, and iOS Runner.
class AlarmSoundOption {
  final String id;
  final String label;

  const AlarmSoundOption({required this.id, required this.label});

  String get previewAssetPath => 'assets/sounds/$id.wav';
  String get iosFilename => '$id.wav';
}

/// Empty id intentionally means the device's normal alarm sound.
const kSystemDefaultSound = AlarmSoundOption(id: '', label: 'Phone default');

/// Add new options only after adding the same lowercase `.wav` file to each
/// platform location described above.
const List<AlarmSoundOption> kAlarmSounds = [
  kSystemDefaultSound,
  AlarmSoundOption(id: 'urgent_beeper', label: 'Urgent beeper'),
  AlarmSoundOption(id: 'siren_pulse', label: 'Siren pulse'),
  AlarmSoundOption(id: 'alert_chime_loud', label: 'Loud alert chime'),
];
