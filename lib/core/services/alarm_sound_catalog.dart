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
  AlarmSoundOption(id: 'custom_sound1', label: 'Custom sound1'),
  AlarmSoundOption(id: 'custom_sound2', label: 'Custom sound2'),  
  AlarmSoundOption(id: 'custom_sound3', label: 'Custom sound3'), 
  AlarmSoundOption(id: 'custom_sound4', label: 'Custom sound4'), 
  AlarmSoundOption(id: 'custom_sound5', label: 'Custom sound5'), 
  AlarmSoundOption(id: 'custom_sound6', label: 'Custom sound6'), 
  AlarmSoundOption(id: 'custom_sound7', label: 'Custom sound7'), 
  AlarmSoundOption(id: 'custom_sound8', label: 'Custom sound8'), 
  AlarmSoundOption(id: 'custom_sound9', label: 'Custom sound9'), 
];
