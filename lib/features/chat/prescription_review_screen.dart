import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';

import '../../core/services/prescription_parser.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/shared_widgets.dart';
import '../../data/models/models.dart';
import '../../providers/profile_provider.dart';
import '../../providers/reminder_provider.dart';
import '../shell/patient_shell.dart';

/// One (medicine, dose-time) pair used while grouping reminders during
/// save — mutable groupId/groupType get filled in as the grouping pass
/// runs, then are copied onto the final [Reminder] objects.
class _MedTimeEntry {
  _MedTimeEntry({required this.med, required this.time});
  final ParsedMedicine med;
  final TimeOfDay time;
  String? groupId;
  String groupType = 'medicine';
}

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
    this.imagePath,
  });

  final String ocrText;
  final List<ParsedMedicine> initialMeds;
  final String? imagePath;

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

  void _addBlank() {
    FocusScope.of(context).unfocus();
    setState(() => _meds.add(ParsedMedicine.blank()));
  }

  void _remove(int i) {
    FocusScope.of(context).unfocus();
    setState(() => _meds.removeAt(i));
  }

  void _setFrequency(int i, int newCount) {
    setState(() {
      final med = _meds[i];
      final oldTimes = med.times;
      // Keep any times the user already customized; only fill/trim the
      // difference so changing 2→3 doesn't discard the two they set.
      final defaults = defaultTimesFor(newCount);
      final newTimes = List<TimeOfDay>.generate(newCount, (idx) {
        if (idx < oldTimes.length) return oldTimes[idx];
        return defaults[idx];
      });
      med.timesPerDay = newCount;
      med.times = newTimes;
    });
  }

  Future<void> _pickTime(int medIndex, int timeIndex) async {
    FocusScope.of(context).unfocus();
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
    if (_saving) return;
    FocusScope.of(context).unfocus();

    final valid = _meds.where((m) => m.name.trim().isNotEmpty).toList();
    if (valid.isEmpty) return;

    setState(() => _saving = true);

    // Flatten every (medicine, dose-time) pair across ALL medicines first,
    // so we can spot doses that land on the exact same clock time even
    // when they belong to different medicines (e.g. two prescriptions
    // both due at 8:00 AM) and combine those into one reminder card.
    final entries = <_MedTimeEntry>[
      for (final med in valid)
        for (final t in med.times) _MedTimeEntry(med: med, time: t),
    ];

    // Bucket by formatted clock time.
    final byTime = <String, List<_MedTimeEntry>>{};
    for (final e in entries) {
      byTime.putIfAbsent(formatTimeOfDay(e.time), () => []).add(e);
    }

    final now = DateTime.now().microsecondsSinceEpoch;
    final unclaimed = <_MedTimeEntry>[]; // not part of a same-time group yet

    for (final timeEntries in byTime.values) {
      final distinctMeds = timeEntries.map((e) => e.med).toSet();
      if (distinctMeds.length > 1) {
        // Multiple different medicines share this exact time — one
        // combined "time" card instead of separate reminders.
        final t = timeEntries.first.time;
        final timeGroupId = '${now}_time_${t.hour}${t.minute}';
        for (final e in timeEntries) {
          e.groupId = timeGroupId;
          e.groupType = 'time';
        }
      } else {
        unclaimed.addAll(timeEntries);
      }
    }

    // Among the doses NOT absorbed into a same-time group above, group a
    // medicine's remaining multiple times under one per-medicine card
    // ("3x daily") as before.
    final byMed = <ParsedMedicine, List<_MedTimeEntry>>{};
    for (final e in unclaimed) {
      byMed.putIfAbsent(e.med, () => []).add(e);
    }
    for (final medEntries in byMed.values) {
      if (medEntries.length <= 1) continue;
      final medGroupId = '${now}_med_${medEntries.first.med.name.hashCode}';
      for (final e in medEntries) {
        e.groupId = medGroupId;
        e.groupType = 'medicine';
      }
    }

    final reminders = entries.map((e) {
      final med = e.med;
      final scheduleLabel =
      med.durationDays != null ? 'Daily · ${med.durationDays} days' : 'Daily';
      return Reminder(
        title: med.name.trim(),
        dose: med.dose.trim(),
        // One exact clock time per reminder — required for the alarm
        // scheduler to actually pick it up (a combined "8 AM & 8 PM"
        // string does not parse).
        time: formatTimeOfDay(e.time),
        schedule: scheduleLabel,
        instructions: med.instructions,
        addedBy: 'MedAI',
        groupId: e.groupId,
        groupType: e.groupType,
      );
    }).toList();

    int count = 0;
    try {
      count = await context.read<ReminderProvider>().addAll(reminders);
    } finally {
      if (mounted) setState(() => _saving = false);
    }

    if (!mounted) return;

    if (count > 0) {
      // Take the user straight to the Reminders tab so the newly-added
      // schedule is immediately visible, instead of dropping them back
      // into the chat.
      Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const PatientShell(initialIndex: 1)),
            (route) => false,
      );
    } else {
      Navigator.of(context).pop(count);
    }
  }

  @override
  Widget build(BuildContext context) {
    final allergies = context.watch<ProfileProvider>().profile.allergies;

    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        backgroundColor: AppColors.paper,
        surfaceTintColor: AppColors.paper,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: AppColors.ink,
        titleSpacing: 0,
        title: Text('Review prescription',
            style: TextStyle(
                fontSize: 16.5.sp,
                fontWeight: FontWeight.w800,
                color: AppColors.ink)),
      ),
      body: SafeArea(
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => FocusScope.of(context).unfocus(),
          child: ListView(
            padding: EdgeInsets.fromLTRB(20.w, 4.h, 20.w, 32.h),
            children: [
              _InfoBanner(),
              if (widget.imagePath != null) ...[
                SizedBox(height: 14.h),
                _ImageThumbnail(path: widget.imagePath!),
              ],
              SizedBox(height: 18.h),
              _SectionLabel(
                  'Medicines · ${_meds.length}'.toUpperCase()),
              SizedBox(height: 10.h),
              for (var i = 0; i < _meds.length; i++)
                Padding(
                  padding: EdgeInsets.only(bottom: 12.h),
                  child: _MedicineEditorCard(
                    index: i,
                    med: _meds[i],
                    allergyFlag:
                    _matchingAllergy(_meds[i].name, allergies),
                    lowConfidence: _meds[i].confidence == 'low',
                    onChanged: () => setState(() {}),
                    onFrequencyChanged: (n) => _setFrequency(i, n),
                    onPickTime: (t) => _pickTime(i, t),
                    onRemove: _meds.length > 1 ? () => _remove(i) : null,
                  ),
                ),
              _AddMedicineButton(onTap: _addBlank),
              if (_hasValidMeds) ...[
                SizedBox(height: 22.h),
                _SectionLabel('PRESCRIPTION SUMMARY'),
                SizedBox(height: 10.h),
                _SummaryPanel(
                    meds: _meds.where((m) => m.name.trim().isNotEmpty).toList()),
              ],
              if (widget.ocrText.trim().isNotEmpty) ...[
                SizedBox(height: 22.h),
                _RawTextPanel(text: widget.ocrText),
              ],
              SizedBox(height: 26.h),
              PrimaryButton(
                label: _saving
                    ? 'Adding…'
                    : _totalReminderCount == 0
                    ? 'Add reminders'
                    : 'Add $_totalReminderCount reminder'
                    '${_totalReminderCount == 1 ? '' : 's'}',
                icon: Icons.alarm_add_rounded,
                onPressed:
                (_hasValidMeds && !_saving) ? _saveReminders : null,
              ),
              SizedBox(height: 10.h),
              Center(
                child: Text(
                  'You choose the exact time for every dose — nothing is '
                      'scheduled automatically.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11.sp, color: AppColors.muted),
                ),
              ),
            ],
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

class _InfoBanner extends StatelessWidget {
  const _InfoBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(14.r),
      decoration: BoxDecoration(
        color: AppColors.aiSoft,
        borderRadius: BorderRadius.circular(16.r),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30.r,
            height: 30.r,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .6),
              borderRadius: BorderRadius.circular(9.r),
            ),
            child: Icon(Icons.auto_awesome_rounded, color: AppColors.ai, size: 16.sp),
          ),
          SizedBox(width: 10.w),
          Expanded(
            child: Text(
              'MedAI read these from your photo. OCR can misread '
                  'handwriting — check every name, dose, and time, then set '
                  'exact times before adding reminders.',
              style: TextStyle(
                  fontSize: 12.5.sp,
                  color: AppColors.ai,
                  fontWeight: FontWeight.w600,
                  height: 1.42),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: 2.w),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11.sp,
          fontWeight: FontWeight.w800,
          color: AppColors.muted,
          letterSpacing: .6,
        ),
      ),
    );
  }
}

class _MedicineEditorCard extends StatelessWidget {
  const _MedicineEditorCard({
    required this.index,
    required this.med,
    required this.onChanged,
    required this.onFrequencyChanged,
    required this.onPickTime,
    required this.onRemove,
    required this.lowConfidence,
    this.allergyFlag,
  });

  final int index;
  final ParsedMedicine med;
  final String? allergyFlag;
  final bool lowConfidence;
  final VoidCallback onChanged;
  final ValueChanged<int> onFrequencyChanged;
  final ValueChanged<int> onPickTime;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final flagged = allergyFlag != null;
    return MCard(
      padding: EdgeInsets.all(16.r),
      border: Border.all(
        color: (flagged || lowConfidence) ? AppColors.warning.withValues(alpha: .55) : AppColors.line,
        width: (flagged || lowConfidence) ? 1.3.w : 1.w,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 26.r,
                height: 26.r,
                margin: EdgeInsets.only(top: 4.h),
                decoration: BoxDecoration(
                  color: AppColors.soft,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text('${index + 1}',
                      style: TextStyle(
                          fontSize: 12.sp,
                          fontWeight: FontWeight.w800,
                          color: AppColors.onSoft)),
                ),
              ),
              SizedBox(width: 10.w),
              Expanded(
                child: TextFormField(
                  initialValue: med.name,
                  onChanged: (v) {
                    med.name = v;
                    onChanged();
                  },
                  style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w700),
                  decoration: const InputDecoration(
                    labelText: 'Medicine name',
                    isDense: true,
                    border: UnderlineInputBorder(),
                  ),
                ),
              ),
              if (onRemove != null)
                InkWell(
                  onTap: onRemove,
                  borderRadius: BorderRadius.circular(20.r),
                  child: Padding(
                    padding: EdgeInsets.all(4.r),
                    child: Icon(Icons.close_rounded, size: 19.sp, color: AppColors.muted),
                  ),
                ),
            ],
          ),
          if (lowConfidence) ...[
            SizedBox(height: 10.h),
            Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 8.h),
              decoration: BoxDecoration(
                color: AppColors.warningSoft,
                borderRadius: BorderRadius.circular(10.r),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.help_outline_rounded, size: 15.sp, color: AppColors.warning),
                  SizedBox(width: 6.w),
                  Expanded(
                    child: Text(
                      "MedAI wasn't fully sure about this reading — please check it carefully against the photo.",
                      style: TextStyle(
                          fontSize: 11.5.sp,
                          color: AppColors.warning,
                          fontWeight: FontWeight.w700,
                          height: 1.3),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (flagged) ...[
            SizedBox(height: 10.h),
            Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 8.h),
              decoration: BoxDecoration(
                color: AppColors.warningSoft,
                borderRadius: BorderRadius.circular(10.r),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.warning_amber_rounded, size: 15.sp, color: AppColors.warning),
                  SizedBox(width: 6.w),
                  Expanded(
                    child: Text(
                      'Possible match with your listed allergy "$allergyFlag" — '
                          'confirm with your doctor before adding this.',
                      style: TextStyle(
                          fontSize: 11.5.sp,
                          color: AppColors.warning,
                          fontWeight: FontWeight.w700,
                          height: 1.3),
                    ),
                  ),
                ],
              ),
            ),
          ],
          SizedBox(height: 14.h),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextFormField(
                  initialValue: med.dose,
                  onChanged: (v) {
                    med.dose = v;
                    onChanged();
                  },
                  style: TextStyle(fontSize: 13.sp),
                  decoration: const InputDecoration(
                    labelText: 'Dose',
                    hintText: '400 mg',
                    isDense: true,
                  ),
                ),
              ),
              SizedBox(width: 10.w),
              Expanded(
                flex: 2,
                child: TextFormField(
                  initialValue: med.durationDays?.toString() ?? '',
                  keyboardType: TextInputType.number,
                  onChanged: (v) {
                    med.durationDays = int.tryParse(v);
                    onChanged();
                  },
                  style: TextStyle(fontSize: 13.sp),
                  decoration: const InputDecoration(
                    labelText: 'Days',
                    hintText: 'Optional',
                    isDense: true,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 12.h),
          TextFormField(
            initialValue: med.instructions,
            onChanged: (v) {
              med.instructions = v;
              onChanged();
            },
            style: TextStyle(fontSize: 13.sp),
            decoration: const InputDecoration(
              labelText: 'Instructions',
              hintText: 'e.g. after food (optional)',
              isDense: true,
            ),
          ),
          SizedBox(height: 16.h),
          Divider(height: 1.h, color: AppColors.line),
          SizedBox(height: 14.h),
          Row(
            children: [
              Icon(Icons.repeat_rounded, size: 15.sp, color: AppColors.muted),
              SizedBox(width: 6.w),
              Text('Times per day',
                  style: TextStyle(
                      fontSize: 12.5.sp,
                      fontWeight: FontWeight.w700,
                      color: AppColors.inkSoft)),
              const Spacer(),
              _Stepper(value: med.timesPerDay, onChanged: onFrequencyChanged),
            ],
          ),
          SizedBox(height: 12.h),
          Wrap(
            spacing: 8.w,
            runSpacing: 8.h,
            children: [
              for (var i = 0; i < med.times.length; i++)
                _TimeChip(time: med.times[i], onTap: () => onPickTime(i)),
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
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 4.h),
      decoration: BoxDecoration(
        color: AppColors.paper,
        borderRadius: BorderRadius.circular(10.r),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _stepBtn(Icons.remove_rounded, value > 1 ? () => onChanged(value - 1) : null),
          SizedBox(
            width: 22.w,
            child: Text('$value',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13.5.sp, fontWeight: FontWeight.w800)),
          ),
          _stepBtn(Icons.add_rounded, value < 6 ? () => onChanged(value + 1) : null),
        ],
      ),
    );
  }

  Widget _stepBtn(IconData icon, VoidCallback? onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(7.r),
      child: Container(
        width: 24.r,
        height: 24.r,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: onTap == null ? Colors.transparent : AppColors.soft,
          borderRadius: BorderRadius.circular(7.r),
        ),
        child: Icon(icon,
            size: 15.sp, color: onTap == null ? AppColors.line : AppColors.primary),
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
          border: Border.all(color: AppColors.primary.withValues(alpha: .25)),
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

class _AddMedicineButton extends StatelessWidget {
  const _AddMedicineButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14.r),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(vertical: 13.h),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14.r),
          border: Border.all(color: AppColors.line, width: 1.2.w),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_rounded, size: 18.sp, color: AppColors.ink),
            SizedBox(width: 7.w),
            Text('Add another medicine',
                style: TextStyle(
                    fontSize: 13.sp, fontWeight: FontWeight.w700, color: AppColors.ink)),
          ],
        ),
      ),
    );
  }
}

class _SummaryPanel extends StatelessWidget {
  const _SummaryPanel({required this.meds});
  final List<ParsedMedicine> meds;

  @override
  Widget build(BuildContext context) {
    final summary = buildProfessionalSummary(meds);
    return MCard(
      color: AppColors.paper,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: SelectableText(
              summary,
              style: TextStyle(
                  fontSize: 12.5.sp,
                  color: AppColors.inkSoft,
                  height: 1.55,
                  fontFamily: 'monospace'),
            ),
          ),
          SizedBox(width: 8.w),
          InkWell(
            borderRadius: BorderRadius.circular(8.r),
            onTap: () {
              Clipboard.setData(ClipboardData(text: summary));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Summary copied')),
              );
            },
            child: Padding(
              padding: EdgeInsets.all(4.r),
              child: Icon(Icons.copy_rounded, size: 17.sp, color: AppColors.muted),
            ),
          ),
        ],
      ),
    );
  }
}

class _RawTextPanel extends StatelessWidget {
  const _RawTextPanel({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.only(top: 8.h),
        title: Text("Didn't come out right? See raw scan text",
            style: TextStyle(
                fontSize: 12.5.sp,
                fontWeight: FontWeight.w700,
                color: AppColors.muted)),
        iconColor: AppColors.muted,
        collapsedIconColor: AppColors.muted,
        children: [
          MCard(
            color: AppColors.paper,
            child: SelectableText(
              text,
              style: TextStyle(
                  fontSize: 12.5.sp, color: AppColors.inkSoft, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _ImageThumbnail extends StatelessWidget {
  const _ImageThumbnail({required this.path});
  final String path;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => _FullScreenViewer(path: path),
        ),
      ),
      child: MCard(
        padding: EdgeInsets.all(8.r),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8.r),
              child: Image.file(
                File(path),
                width: 60.r,
                height: 60.r,
                fit: BoxFit.cover,
              ),
            ),
            SizedBox(width: 12.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Prescription Photo',
                      style: TextStyle(
                          fontSize: 14.sp, fontWeight: FontWeight.w700)),
                  Text('Tap to view full size',
                      style: TextStyle(
                          fontSize: 12.sp, color: AppColors.muted)),
                ],
              ),
            ),
            Icon(Icons.fullscreen_rounded, color: AppColors.muted),
          ],
        ),
      ),
    );
  }
}

class _FullScreenViewer extends StatelessWidget {
  const _FullScreenViewer({required this.path});
  final String path;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Center(
        child: InteractiveViewer(
          child: Image.file(File(path)),
        ),
      ),
    );
  }
}