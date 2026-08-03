import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/services/alarm_sound_catalog.dart';
import '../../core/services/alarm_sound_prefs.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/shared_widgets.dart';
import '../../providers/reminder_provider.dart';

/// Selects and previews the sound used by every subsequently scheduled alarm.
class AlarmSoundScreen extends StatefulWidget {
  const AlarmSoundScreen({super.key});

  @override
  State<AlarmSoundScreen> createState() => _AlarmSoundScreenState();
}

class _AlarmSoundScreenState extends State<AlarmSoundScreen> {
  final _player = AudioPlayer();
  String? _selectedId;
  String? _previewingId;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
    _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _previewingId = null);
    });
  }

  Future<void> _load() async {
    final selected = await AlarmSoundPrefs.instance.getSelected();
    if (!mounted) return;
    setState(() {
      _selectedId = selected.id;
      _loading = false;
    });
  }

  Future<void> _select(AlarmSoundOption option) async {
    setState(() => _selectedId = option.id);
    await AlarmSoundPrefs.instance.setSelected(option);
    if (!mounted) return;
    await context.read<ReminderProvider>().rescheduleEnabledReminders();
    if (!mounted) return;
    showToast(context, 'Alarm sound set to ${option.label}');
  }

  Future<void> _togglePreview(AlarmSoundOption option) async {
    if (option.id.isEmpty) return;
    if (_previewingId == option.id) {
      await _player.stop();
      if (mounted) setState(() => _previewingId = null);
      return;
    }
    await _player.stop();
    try {
      await _player.play(
        AssetSource(option.previewAssetPath.replaceFirst('assets/', '')),
      );
      if (mounted) setState(() => _previewingId = option.id);
    } catch (_) {
      if (mounted) showToast(context, 'Unable to preview this sound');
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Alarm sound', style: GoogleFonts.sora(fontWeight: FontWeight.w700)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  'Choose the sound used when it is time to take a medicine. '
                  'Your choice is used for every new or updated reminder.',
                  style: TextStyle(color: AppColors.muted, fontSize: 13),
                ),
                const SizedBox(height: 16),
                for (final option in kAlarmSounds) ...[
                  _SoundTile(
                    option: option,
                    selected: _selectedId == option.id,
                    previewing: _previewingId == option.id,
                    onSelect: () => _select(option),
                    onPreview: () => _togglePreview(option),
                  ),
                  const SizedBox(height: 10),
                ],
              ],
            ),
    );
  }
}

class _SoundTile extends StatelessWidget {
  const _SoundTile({
    required this.option,
    required this.selected,
    required this.previewing,
    required this.onSelect,
    required this.onPreview,
  });

  final AlarmSoundOption option;
  final bool selected;
  final bool previewing;
  final VoidCallback onSelect;
  final VoidCallback onPreview;

  @override
  Widget build(BuildContext context) {
    return MCard(
      onTap: onSelect,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Row(
        children: [
          Icon(
            selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
            color: selected ? AppColors.primary : AppColors.muted,
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(option.label, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600))),
          if (option.id.isNotEmpty)
            IconButton(
              onPressed: onPreview,
              icon: Icon(
                previewing ? Icons.stop_circle_rounded : Icons.play_circle_outline_rounded,
                color: AppColors.primary,
              ),
            ),
        ],
      ),
    );
  }
}
