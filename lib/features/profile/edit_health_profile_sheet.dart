import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/shared_widgets.dart';
import '../../providers/profile_provider.dart';

const _bloodGroups = ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'];

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// Opens the "Edit Health Profile" bottom sheet. Reads the current
/// [HealthProfile] from [ProfileProvider], lets the user edit it, and
/// writes the result back to Firestore via [ProfileProvider.updateProfile]
/// on Save. The provider's snapshot listener then refreshes the rest of
/// the app automatically — no manual state sync needed here.
Future<void> showEditHealthProfileSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _EditHealthProfileSheet(),
  );
}

class _EditHealthProfileSheet extends StatefulWidget {
  const _EditHealthProfileSheet();

  @override
  State<_EditHealthProfileSheet> createState() =>
      _EditHealthProfileSheetState();
}

class _EditHealthProfileSheetState extends State<_EditHealthProfileSheet> {
  late String _bloodType;
  late final TextEditingController _feetCtrl;
  late final TextEditingController _inchesCtrl;
  late final TextEditingController _weightCtrl;
  DateTime? _dob;

  late List<String> _allergies;
  late List<String> _conditions;
  late List<String> _medications;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final p = context.read<ProfileProvider>().profile;
    _bloodType = _bloodGroups.contains(p.bloodType)
        ? p.bloodType
        : _bloodGroups.first;
    _feetCtrl = TextEditingController(
      text: p.heightIn > 0 ? (p.heightIn ~/ 12).toString() : '',
    );
    _inchesCtrl = TextEditingController(
      text: p.heightIn > 0 ? (p.heightIn % 12).toString() : '',
    );
    _weightCtrl = TextEditingController(
      text: p.weightLb > 0 ? p.weightLb.toString() : '',
    );
    _dob = _parseDob(p.dob);
    _allergies = List.of(p.allergies);
    _conditions = List.of(p.conditions);
    _medications = List.of(p.medications);
  }

  @override
  void dispose() {
    _feetCtrl.dispose();
    _inchesCtrl.dispose();
    _weightCtrl.dispose();
    super.dispose();
  }

  DateTime? _parseDob(String dob) {
    if (dob.trim().isEmpty) return null;
    final parts = dob.split(' ');
    if (parts.length != 3) return null;
    final day = int.tryParse(parts[0]);
    final monthIdx = _months.indexOf(
      parts[1].length >= 3 ? parts[1].substring(0, 3) : parts[1],
    );
    final year = int.tryParse(parts[2]);
    if (day == null || monthIdx == -1 || year == null) return null;
    return DateTime(year, monthIdx + 1, day);
  }

  String _formatDob(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dob ?? DateTime(now.year - 25, now.month, now.day),
      firstDate: DateTime(1900),
      lastDate: now,
    );
    if (picked != null) setState(() => _dob = picked);
  }

  Future<void> _save() async {
    final feet = int.tryParse(_feetCtrl.text) ?? 0;
    final inches = int.tryParse(_inchesCtrl.text) ?? 0;
    final weight = int.tryParse(_weightCtrl.text) ?? 0;

    final prov = context.read<ProfileProvider>();
    final updated = prov.profile.copyWith(
      bloodType: _bloodType,
      heightIn: feet * 12 + inches,
      weightLb: weight,
      dob: _dob != null ? _formatDob(_dob!) : '',
      allergies: _allergies,
      conditions: _conditions,
      medications: _medications,
    );

    setState(() => _saving = true);
    try {
      await prov.updateProfile(updated);
      if (!mounted) return;
      Navigator.of(context).pop();
      showToast(
        context,
        'Profile updated successfully!',
        color: AppColors.success,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showToast(context, 'Could not save profile: $e', color: AppColors.danger);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: DraggableScrollableSheet(
        initialChildSize: 0.9,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) {
          return Container(
            decoration: BoxDecoration(
              color: AppColors.paper,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(28),
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.ink.withValues(alpha: .10),
                  blurRadius: 30,
                  offset: const Offset(0, -8),
                ),
              ],
            ),
            child: Column(
              children: [
                const SizedBox(height: 12),
                const SheetHandle(),
                Expanded(
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
                    children: [
                      const SheetHeader(
                        icon: Icons.favorite_rounded,
                        color: AppColors.primary,
                        title: 'Edit Health Profile',
                        subtitle:
                            'Update your medical information to improve recommendations.',
                      ),
                      const SizedBox(height: 22),
                      const SectionHeader('Basic information'),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: _bloodDropdown()),
                          const SizedBox(width: 12),
                          Expanded(child: _heightField()),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: _weightField()),
                          const SizedBox(width: 12),
                          Expanded(child: _dobField()),
                        ],
                      ),
                      const SizedBox(height: 20),
                      const SectionHeader('Allergies'),
                      _ChipEditor(
                        values: _allergies,
                        hint: 'Add Allergy',
                        background: AppColors.dangerSoft,
                        foreground: AppColors.danger,
                        onChanged: (v) => setState(() => _allergies = v),
                      ),
                      const SizedBox(height: 20),
                      const SectionHeader('Conditions'),
                      _ChipEditor(
                        values: _conditions,
                        hint: 'Add Condition',
                        background: AppColors.warningSoft,
                        foreground: AppColors.warning,
                        onChanged: (v) => setState(() => _conditions = v),
                      ),
                      const SizedBox(height: 20),
                      const SectionHeader('Medications'),
                      _ChipEditor(
                        values: _medications,
                        hint: 'Add Medication',
                        background: AppColors.soft,
                        foreground: AppColors.onSoft,
                        onChanged: (v) => setState(() => _medications = v),
                      ),
                      const SizedBox(height: 30),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _saving
                                  ? null
                                  : () => Navigator.of(context).pop(),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.inkSoft,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                                side: const BorderSide(
                                  color: AppColors.line,
                                  width: 1.3,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(15),
                                ),
                                textStyle: const TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              child: const Text('Cancel'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: PrimaryButton(
                              label: _saving ? 'Saving…' : 'Save Changes',
                              onPressed: _saving ? null : _save,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _bloodDropdown() {
    return _FieldShell(
      icon: Icons.water_drop_outlined,
      label: 'Blood Group',
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _bloodType,
          isExpanded: true,
          items: _bloodGroups
              .map((b) => DropdownMenuItem(value: b, child: Text(b)))
              .toList(),
          onChanged: (v) => setState(() => _bloodType = v ?? _bloodType),
        ),
      ),
    );
  }

  Widget _heightField() {
    return _FieldShell(
      icon: Icons.height_rounded,
      label: 'Height',
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _feetCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                isDense: true,
                border: InputBorder.none,
                suffixText: 'ft',
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _inchesCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                isDense: true,
                border: InputBorder.none,
                suffixText: 'in',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _weightField() {
    return _FieldShell(
      icon: Icons.monitor_weight_outlined,
      label: 'Weight',
      child: TextField(
        controller: _weightCtrl,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(
          isDense: true,
          border: InputBorder.none,
          suffixText: 'lb',
        ),
      ),
    );
  }

  Widget _dobField() {
    return _FieldShell(
      icon: Icons.calendar_today_outlined,
      label: 'Date of Birth',
      child: GestureDetector(
        onTap: _pickDob,
        child: Text(
          _dob != null ? _formatDob(_dob!) : 'Select date',
          style: TextStyle(
            fontSize: 14,
            color: _dob != null ? AppColors.ink : AppColors.muted,
          ),
        ),
      ),
    );
  }
}

class _FieldShell extends StatelessWidget {
  const _FieldShell({
    required this.icon,
    required this.label,
    required this.child,
  });

  final IconData icon;
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: AppColors.line),
        boxShadow: [
          BoxShadow(
            color: AppColors.ink.withValues(alpha: .03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: AppColors.muted),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(fontSize: 11.5, color: AppColors.muted),
              ),
            ],
          ),
          const SizedBox(height: 4),
          child,
        ],
      ),
    );
  }
}

/// Chip list with inline "+ Add X" entry and tap-to-remove chips, used
/// for Allergies / Conditions / Medications.
class _ChipEditor extends StatefulWidget {
  const _ChipEditor({
    required this.values,
    required this.hint,
    required this.background,
    required this.foreground,
    required this.onChanged,
  });

  final List<String> values;
  final String hint;
  final Color background;
  final Color foreground;
  final ValueChanged<List<String>> onChanged;

  @override
  State<_ChipEditor> createState() => _ChipEditorState();
}

class _ChipEditorState extends State<_ChipEditor> {
  bool _adding = false;
  final _ctrl = TextEditingController();

  void _commit() {
    final text = _ctrl.text.trim();
    if (text.isNotEmpty && !widget.values.contains(text)) {
      widget.onChanged([...widget.values, text]);
    }
    _ctrl.clear();
    setState(() => _adding = false);
  }

  void _remove(String v) {
    widget.onChanged(widget.values.where((e) => e != v).toList());
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final v in widget.values)
          MChip(
            v,
            background: widget.background,
            foreground: widget.foreground,
            icon: Icons.close_rounded,
            onTap: () => _remove(v),
          ),
        if (_adding)
          SizedBox(
            width: 170,
            child: TextField(
              controller: _ctrl,
              autofocus: true,
              onSubmitted: (_) => _commit(),
              onTapOutside: (_) => _commit(),
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
                hintText: 'Type and press enter',
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
              ),
            ),
          )
        else
          OutlinedButton.icon(
            onPressed: () => setState(() => _adding = true),
            icon: const Icon(Icons.add_rounded, size: 16),
            label: Text(widget.hint),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: BorderSide(color: AppColors.primary.withValues(alpha: .4)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
      ],
    );
  }
}
