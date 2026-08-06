import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';

import '../../core/services/prescription_parser.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/shared_widgets.dart';
import '../../data/models/models.dart';
import '../../providers/profile_provider.dart';
import '../../providers/reminder_provider.dart';

/// Where the user confirms what MedAI read off a scanned prescription —
/// medicine name, dose, how many times a day, and the EXACT clock time for
/// each dose — before anything becomes a real alarm reminder. Nothing here
/// is auto-added; every field starts as a best-effort guess and the user
/// has full control before tapping "Add reminders".
class PrescriptionReviewScreen extends StatefulWidget {
  const PrescriptionReviewScreen({
    super.key,
    required this.ocrText,
    required this.initialMeds,
  });

  final String ocrText;
  final List<ParsedMedicine> initialMeds;

  @override
  State<PrescriptionReviewScreen> createState() =>
      _PrescriptionReviewScreenState();
}

class _PrescriptionReviewScreenState extends State<PrescriptionReviewScreen> {
  late List<ParsedMedicine> _meds;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _meds = widget.initialMeds.isEmpty
        ? [ParsedMedicine.blank()]
        : widget.initialMeds;
  }

  void _addBlank() => setState(() => _meds.add(ParsedMedicine.blank()));

  void _remove(int i) => setState(() => _meds.removeAt(i));

  void _setFrequency(int i, int newCount) {
    setState(() {
      final med = _meds[i];
      final oldTimes = med.times;
      // Keep any times the user already customized; only fill/trim the
      // difference so changing 2→3 doesn't discard the two they set.
      final newTimes = List<TimeOfDay>.generate(newCount, (idx) {
        if (idx < oldTimes.length) return oldTimes[idx];
        return defaultTimesFor(newCount)[idx];
      });
      med.timesPerDay = newCount;
      med.times = newTimes;
    });
  }

  Future<void> _pickTime(int medIndex, int timeIndex) async {
    final med = _meds[medIndex];
    final picked = await showTimePicker(
      context: context,
      initialTime: med.times[timeIndex],
      helpText: 'Exact dose time',
    );
    if (picked == null) return;
    setState(() => med.times[timeIndex] = picked);
  }

  bool get _hasValidMeds => _meds.any((m) => m.name.trim().isNotEmpty);

  int get _totalReminderCount => _meds
      .where((m) => m.name.trim().isNotEmpty)
      .fold(0, (sum, m) => sum + m.times.length);

  Future<void> _saveReminders() async {
    final valid = _meds.where((m) => m.name.trim().isNotEmpty).toList();
    if (valid.isEmpty) return;

    setState(() => _saving = true);

    final reminders = <Reminder>[];
    for (final med in valid) {
      final scheduleLabel =
          med.durationDays != null ? 'Daily · ${med.durationDays} days' : 'Daily';
      for (final t in med.times) {
        reminders.add(Reminder(
          title: med.name.trim(),
          dose: med.dose.trim(),
          time: formatTimeOfDay(t), // one exact clock time per reminder —
          // required for the alarm scheduler to actually pick it up.
          schedule: scheduleLabel,
          instructions: med.instructions,
          addedBy: 'MedAI',
        ));
      }
    }

    final count = await context.read<ReminderProvider>().addAll(reminders);

    if (!mounted) return;
    setState(() => _saving = false);
    Navigator.of(context).pop(count);
  }

  @override
  Widget build(BuildContext context) {
    final allergies = context.watch<ProfileProvider>().profile.allergies;

    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        backgroundColor: AppColors.paper,
        elevation: 0,
        foregroundColor: AppColors.ink,
        title: Text('Review prescription',
            style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w800)),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(20.w, 8.h, 20.w, 4.h),
              child: Container(
                padding: EdgeInsets.all(12.r),
                decoration: BoxDecoration(
                  color: AppColors.aiSoft,
                  borderRadius: BorderRadius.circular(14.r),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline_rounded,
                        color: AppColors.ai, size: 18.sp),
                    SizedBox(width: 8.w),
                    Expanded(
                      child: Text(
                        'MedAI read these from your photo — OCR can misread '
                        'handwriting. Check every name, dose, and time '
                        'below, then set the exact times before adding '
                        'reminders.',
                        style: TextStyle(
                            fontSize: 12.sp,
                            color: AppColors.ai,
                            fontWeight: FontWeight.w600,
                            height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.fromLTRB(20.w, 12.h, 20.w, 100.h),
                children: [
                  for (var i = 0; i < _meds.length; i++)
                    Padding(
                      padding: EdgeInsets.only(bottom: 14.h),
                      child: _MedicineEditorCard(
                        med: _meds[i],
                        allergyFlag: _matchingAllergy(_meds[i].name, allergies),
                        onChanged: () => setState(() {}),
                        onFrequencyChanged: (n) => _setFrequency(i, n),
                        onPickTime: (t) => _pickTime(i, t),
                        onRemove: _meds.length > 1 ? () => _remove(i) : null,
                      ),
                    ),
                  OutlinedButton.icon(
                    onPressed: _addBlank,
                    icon: Icon(Icons.add_rounded, size: 18.sp),
                    label: const Text('Add another medicine'),
                    style: OutlinedButton.styleFrom(
                      padding: EdgeInsets.symmetric(vertical: 13.h),
                      side: const BorderSide(color: AppColors.line),
                      foregroundColor: AppColors.ink,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14.r)),
                    ),
                  ),
                  if (widget.ocrText.trim().isNotEmpty) ...[
                    SizedBox(height: 18.h),
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: Text("Didn't come out right? See raw scan text",
                          style: TextStyle(
                              fontSize: 12.5.sp,
                              fontWeight: FontWeight.w700,
                              color: AppColors.muted)),
                      children: [
                        MCard(
                          child: SelectableText(
                            widget.ocrText,
                            style: TextStyle(
                                fontSize: 12.5.sp,
                                color: AppColors.inkSoft,
                                height: 1.5),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(20.w, 10.h, 20.w, 14.h),
          child: PrimaryButton(
            label: _saving
                ? 'Adding…'
                : _totalReminderCount == 0
                    ? 'Add reminders'
                    : 'Add $_totalReminderCount reminder${_totalReminderCount == 1 ? '' : 's'}',
            icon: Icons.alarm_add_rounded,
            onPressed: (_hasValidMeds && !_saving) ? _saveReminders : null,
          ),
        ),
      ),
    );
  }

  /// Simple case-insensitive substring match against the user's listed
  /// allergies — a heuristic warning only, never a block. The user always
  /// has final say on what gets added.
  String? _matchingAllergy(String medName, List<String> allergies) {
    final name = medName.trim().toLowerCase();
    if (name.isEmpty) return null;
    for (final allergy in allergies) {
      final a = allergy.trim().toLowerCase();
      if (a.isEmpty) continue;
      if (name.contains(a) || a.contains(name)) return allergy;
    }
    return null;
  }
}

class _MedicineEditorCard extends StatelessWidget {
  const _MedicineEditorCard({
    required this.med,
    required this.onChanged,
    required this.onFrequencyChanged,
    required this.onPickTime,
    required this.onRemove,
    this.allergyFlag,
  });

  final ParsedMedicine med;
  final String? allergyFlag;
  final VoidCallback onChanged;
  final ValueChanged<int> onFrequencyChanged;
  final ValueChanged<int> onPickTime;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return MCard(
      border: allergyFlag != null
          ? Border.all(color: AppColors.warning, width: 1.2.w)
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  initialValue: med.name,
                  onChanged: (v) {
                    med.name = v;
                    onChanged();
                  },
                  style: TextStyle(fontSize: 14.5.sp, fontWeight: FontWeight.w700),
                  decoration: const InputDecoration(
                    labelText: 'Medicine name',
                    isDense: true,
                  ),
                ),
              ),
              if (onRemove != null)
                IconButton(
                  onPressed: onRemove,
                  icon: Icon(Icons.close_rounded, size: 20.sp, color: AppColors.muted),
                ),
            ],
          ),
          if (allergyFlag != null) ...[
            SizedBox(height: 4.h),
            Row(
              children: [
                Icon(Icons.warning_amber_rounded, size: 15.sp, color: AppColors.warning),
                SizedBox(width: 5.w),
                Expanded(
                  child: Text(
                    'Possible match with your listed allergy "$allergyFlag" — '
                    'confirm with your doctor before adding this.',
                    style: TextStyle(
                        fontSize: 11.5.sp,
                        color: AppColors.warning,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ],
          SizedBox(height: 10.h),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  initialValue: med.dose,
                  onChanged: (v) {
                    med.dose = v;
                    onChanged();
                  },
                  style: TextStyle(fontSize: 13.sp),
                  decoration: const InputDecoration(
                    labelText: 'Dose (e.g. 400 mg)',
                    isDense: true,
                  ),
                ),
              ),
              SizedBox(width: 10.w),
              Expanded(
                child: TextFormField(
                  initialValue: med.durationDays?.toString() ?? '',
                  keyboardType: TextInputType.number,
                  onChanged: (v) {
                    med.durationDays = int.tryParse(v);
                    onChanged();
                  },
                  style: TextStyle(fontSize: 13.sp),
                  decoration: const InputDecoration(
                    labelText: 'Days (optional)',
                    isDense: true,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 10.h),
          TextFormField(
            initialValue: med.instructions,
            onChanged: (v) {
              med.instructions = v;
              onChanged();
            },
            style: TextStyle(fontSize: 13.sp),
            decoration: const InputDecoration(
              labelText: 'Instructions (optional) — e.g. after food',
              isDense: true,
            ),
          ),
          SizedBox(height: 14.h),
          Row(
            children: [
              Text('Times per day',
                  style: TextStyle(fontSize: 12.5.sp, fontWeight: FontWeight.w700)),
              const Spacer(),
              _Stepper(
                value: med.timesPerDay,
                onChanged: onFrequencyChanged,
              ),
            ],
          ),
          SizedBox(height: 10.h),
          Wrap(
            spacing: 8.w,
            runSpacing: 8.h,
            children: [
              for (var i = 0; i < med.times.length; i++)
                _TimeChip(
                  time: med.times[i],
                  onTap: () => onPickTime(i),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({required this.value, required this.onChanged});
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _stepBtn(Icons.remove_rounded, value > 1 ? () => onChanged(value - 1) : null),
        SizedBox(
          width: 26.w,
          child: Text('$value',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w800)),
        ),
        _stepBtn(Icons.add_rounded, value < 6 ? () => onChanged(value + 1) : null),
      ],
    );
  }

  Widget _stepBtn(IconData icon, VoidCallback? onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: onTap == null ? AppColors.line.withValues(alpha: .5) : AppColors.soft,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon,
            size: 16, color: onTap == null ? AppColors.muted : AppColors.primary),
      ),
    );
  }
}

class _TimeChip extends StatelessWidget {
  const _TimeChip({required this.time, required this.onTap});
  final TimeOfDay time;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10.r),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
        decoration: BoxDecoration(
          color: AppColors.soft,
          borderRadius: BorderRadius.circular(10.r),
          border: Border.all(color: AppColors.primary.withValues(alpha: .3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.access_time_rounded, size: 14.sp, color: AppColors.primary),
            SizedBox(width: 5.w),
            Text(formatTimeOfDay(time),
                style: TextStyle(
                    fontSize: 12.5.sp,
                    fontWeight: FontWeight.w700,
                    color: AppColors.onSoft)),
          ],
        ),
      ),
    );
  }
}