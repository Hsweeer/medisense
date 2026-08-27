import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/services/caregiver_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/shared_widgets.dart';
import '../../../data/models/caregiver_models.dart';
import '../../../data/models/models.dart';
import '../../reminders/reminder_form_helpers.dart';

/// Full-screen "create a reminder for someone I care for" flow, styled to
/// match [AddReminderFormScreen] exactly (category banner, suggestion
/// chips, multi-time picker with a clock icon, day-of-week schedule) with
/// one extra section up top so the caregiver can choose who it's for.
class CreateCaregiverReminderScreen extends StatefulWidget {
  const CreateCaregiverReminderScreen({super.key});

  @override
  State<CreateCaregiverReminderScreen> createState() =>
      _CreateCaregiverReminderScreenState();
}

class _CreateCaregiverReminderScreenState
    extends State<CreateCaregiverReminderScreen> {
  final Set<String> _selectedRecipientUids = {};

  ReminderCategory _category = ReminderCategory.medication;
  bool _directAssign = true;

  final TextEditingController _name = TextEditingController();
  final TextEditingController _value = TextEditingController();
  final TextEditingController _instructions = TextEditingController();

  final List<String> _times = [];
  String _schedule = 'Daily';
  Set<int> _selectedDays = {};
  bool _saving = false;

  static const _scheduleOptions = ['Daily', 'Weekdays', 'Mon · Wed · Fri', 'Custom'];

  @override
  void dispose() {
    _name.dispose();
    _value.dispose();
    _instructions.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    FocusScope.of(context).unfocus();

    if (_selectedRecipientUids.isEmpty) {
      showToast(context, 'Please select at least one recipient', color: AppColors.danger);
      return;
    }
    final name = _name.text.trim();
    if (name.isEmpty) {
      showToast(context, 'Please enter a name first', color: AppColors.danger);
      return;
    }

    setState(() => _saving = true);

    String finalSchedule = _schedule;
    if (_schedule == 'Custom') {
      final sorted = _selectedDays.toList()..sort();
      const dayNames = ['', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      finalSchedule = sorted.map((d) => dayNames[d]).join(' · ');
    }
    final joinedTimes = _times.isEmpty ? '9:00 AM' : _times.join(', ');

    final reminder = Reminder(
      title: name,
      dose: _directAssign
          ? (_value.text.trim().isEmpty ? _category.defaultValue : _value.text.trim())
          : '',
      time: joinedTimes,
      schedule: finalSchedule,
      instructions: _instructions.text.trim(),
      addedBy: 'caregiver',
    );

    try {
      await CaregiverService.instance.createReminderForRecipients(
        reminder: reminder,
        recipientUids: _selectedRecipientUids.toList(),
      );
      if (!mounted) return;
      showToast(context, '$name added for your recipients', color: _category.color);
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      showToast(context, 'Could not create reminder: $e', color: AppColors.danger);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = _category.color;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: AppColors.paper,
        appBar: AppBar(
          backgroundColor: AppColors.paper,
          elevation: 0,
          title: Text('New reminder for someone',
              style: GoogleFonts.sora(
                  fontSize: 17.sp, fontWeight: FontWeight.w800, color: AppColors.ink)),
        ),
        body: SafeArea(
          child: ListView(
            padding: EdgeInsets.fromLTRB(20.w, 4.h, 20.w, 40.h),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            children: [
              _SectionLabel('RECIPIENTS'),
              SizedBox(height: 10.h),
              _RecipientPicker(
                selectedUids: _selectedRecipientUids,
                onToggle: (uid, selected) {
                  setState(() {
                    if (selected) {
                      _selectedRecipientUids.add(uid);
                    } else {
                      _selectedRecipientUids.remove(uid);
                    }
                  });
                },
              ),
              SizedBox(height: 26.h),
              _SectionLabel('CATEGORY'),
              SizedBox(height: 10.h),
              Wrap(
                spacing: 8.w,
                runSpacing: 8.h,
                children: [
                  for (final c in ReminderCategory.values)
                    _CategoryChip(
                      category: c,
                      selected: _category == c,
                      onTap: () => setState(() {
                        _category = c;
                        _name.clear();
                      }),
                    ),
                ],
              ),
              SizedBox(height: 14.h),
              _CategoryBanner(category: _category),
              SizedBox(height: 26.h),
              _SectionLabel(_category.nameSectionLabel),
              SizedBox(height: 10.h),
              Wrap(
                spacing: 8.w,
                runSpacing: 8.h,
                children: [
                  for (final s in _category.suggestions)
                    _SuggestionChip(
                      label: s,
                      selected: _name.text.trim() == s,
                      color: accent,
                      onTap: () => setState(() => _name.text = s),
                    ),
                ],
              ),
              SizedBox(height: 6.h),
              Text('Tap a suggestion or type your own below.',
                  style: TextStyle(fontSize: 11.5.sp, color: AppColors.muted)),
              SizedBox(height: 12.h),
              TextField(
                controller: _name,
                style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600),
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: _category.nameFieldHint,
                  prefixIcon: Icon(_category.icon, size: 22.sp, color: accent),
                ),
              ),
              SizedBox(height: 20.h),
              Row(
                children: [
                  Expanded(
                    child: _TogglePill(
                      label: 'Direct assign',
                      selected: _directAssign,
                      color: accent,
                      onTap: () => setState(() => _directAssign = true),
                    ),
                  ),
                  SizedBox(width: 10.w),
                  Expanded(
                    child: _TogglePill(
                      label: 'Simple note',
                      selected: !_directAssign,
                      color: accent,
                      onTap: () => setState(() => _directAssign = false),
                    ),
                  ),
                ],
              ),
              if (_directAssign) ...[
                SizedBox(height: 12.h),
                TextField(
                  controller: _value,
                  style: TextStyle(fontSize: 15.sp),
                  decoration: InputDecoration(
                    hintText: _category.valueFieldHint,
                    prefixIcon: Icon(Icons.fitness_center_rounded, size: 22.sp),
                  ),
                ),
              ],
              SizedBox(height: 26.h),
              _SectionLabel('WHEN'),
              SizedBox(height: 10.h),
              Wrap(
                spacing: 8.w,
                runSpacing: 8.h,
                children: [
                  for (final t in _times)
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 9.h),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: .10),
                        borderRadius: BorderRadius.circular(12.r),
                        border: Border.all(color: accent.withValues(alpha: .3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.access_time_filled_rounded, color: accent, size: 16.sp),
                          SizedBox(width: 6.w),
                          Text(t,
                              style: TextStyle(
                                  fontSize: 14.sp,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.ink)),
                          SizedBox(width: 4.w),
                          GestureDetector(
                            onTap: () {
                              if (_times.length > 1) {
                                setState(() => _times.remove(t));
                              }
                            },
                            child: Icon(Icons.close_rounded, size: 16.sp, color: AppColors.muted),
                          ),
                        ],
                      ),
                    ),
                  GestureDetector(
                    onTap: () async {
                      FocusScope.of(context).unfocus();
                      final picked = await pickTimeValue(context);
                      if (picked == null) return;
                      final label = formatTimeOfDay(picked);
                      if (!_times.contains(label)) {
                        setState(() {
                          _times.add(label);
                          int minutesOf(String s) {
                            final t = parseTimeLabel(s) ?? TimeOfDay.now();
                            return t.hour * 60 + t.minute;
                          }
                          _times.sort((a, b) => minutesOf(a).compareTo(minutesOf(b)));
                        });
                      }
                    },
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 9.h),
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        borderRadius: BorderRadius.circular(12.r),
                        border: Border.all(color: AppColors.line),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.add_rounded, size: 16.sp, color: accent),
                          SizedBox(width: 4.w),
                          Text('Add time',
                              style: TextStyle(
                                  fontSize: 13.sp, fontWeight: FontWeight.w700, color: accent)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 6.h),
              Text('Add every time this is due — one reminder handles all of them.',
                  style: TextStyle(fontSize: 11.5.sp, color: AppColors.muted)),
              SizedBox(height: 26.h),
              _SectionLabel('SCHEDULE'),
              SizedBox(height: 12.h),
              Wrap(
                spacing: 8.w,
                runSpacing: 10.h,
                children: [
                  for (final s in _scheduleOptions)
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _schedule = s;
                          if (s == 'Daily') _selectedDays = {};
                          if (s == 'Weekdays') _selectedDays = {1, 2, 3, 4, 5};
                          if (s == 'Mon · Wed · Fri') _selectedDays = {1, 3, 5};
                        });
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
                        decoration: BoxDecoration(
                          color: s == _schedule ? accent : AppColors.card,
                          borderRadius: BorderRadius.circular(12.r),
                          border: Border.all(color: s == _schedule ? accent : AppColors.line),
                        ),
                        child: Text(s,
                            style: TextStyle(
                                fontSize: 13.sp,
                                fontWeight: FontWeight.w700,
                                color: s == _schedule ? Colors.white : AppColors.muted)),
                      ),
                    ),
                ],
              ),
              if (_schedule == 'Custom') ...[
                SizedBox(height: 20.h),
                Container(
                  padding: EdgeInsets.all(12.r),
                  decoration: BoxDecoration(
                      color: _category.softColor, borderRadius: BorderRadius.circular(16.r)),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      for (int i = 1; i <= 7; i++)
                        DayButton(
                          day: i,
                          isSelected: _selectedDays.contains(i),
                          color: accent,
                          onTap: () {
                            setState(() {
                              if (_selectedDays.contains(i)) {
                                if (_selectedDays.length > 1) _selectedDays.remove(i);
                              } else {
                                _selectedDays.add(i);
                              }
                            });
                          },
                        ),
                    ],
                  ),
                ),
              ],
              SizedBox(height: 26.h),
              _SectionLabel('NOTES'),
              SizedBox(height: 10.h),
              TextField(
                controller: _instructions,
                style: TextStyle(fontSize: 15.sp),
                decoration: InputDecoration(
                  hintText: 'Additional instructions (optional)',
                  prefixIcon: Icon(Icons.notes_rounded, size: 22.sp),
                ),
              ),
              SizedBox(height: 34.h),
              PrimaryButton(
                label: _saving ? 'Saving…' : 'Save reminder',
                color: accent,
                onPressed: _saving ? null : _save,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Recipient list styled as tappable pill chips with an avatar initial —
/// replaces the raw Material [FilterChip] list the screen used before.
class _RecipientPicker extends StatelessWidget {
  const _RecipientPicker({required this.selectedUids, required this.onToggle});

  final Set<String> selectedUids;
  final void Function(String uid, bool selected) onToggle;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<CaregiverLink>>(
      stream: CaregiverService.instance.myAcceptedRecipients(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Container(
            padding: EdgeInsets.all(16.r),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(16.r),
              border: Border.all(color: AppColors.line),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 16.r,
                  height: 16.r,
                  child: const CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 12.w),
                Text('Loading your recipients…',
                    style: TextStyle(fontSize: 13.sp, color: AppColors.muted)),
              ],
            ),
          );
        }

        final links = snapshot.data!;
        if (links.isEmpty) {
          return Container(
            padding: EdgeInsets.all(14.r),
            decoration: BoxDecoration(
              color: AppColors.soft,
              borderRadius: BorderRadius.circular(16.r),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded, size: 20.sp, color: AppColors.onSoft),
                SizedBox(width: 10.w),
                Expanded(
                  child: Text('No accepted recipients yet — send a request first.',
                      style: TextStyle(
                          fontSize: 12.5.sp,
                          fontWeight: FontWeight.w600,
                          color: AppColors.onSoft)),
                ),
              ],
            ),
          );
        }

        return Wrap(
          spacing: 8.w,
          runSpacing: 8.h,
          children: links.map((l) {
            final selected = selectedUids.contains(l.recipientUid);
            return GestureDetector(
              onTap: () => onToggle(l.recipientUid, !selected),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
                decoration: BoxDecoration(
                  color: selected ? AppColors.primary : AppColors.card,
                  borderRadius: BorderRadius.circular(99.r),
                  border: Border.all(
                      color: selected ? AppColors.primary : AppColors.line),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(
                      radius: 10.r,
                      backgroundColor: selected
                          ? Colors.white.withValues(alpha: .25)
                          : AppColors.soft,
                      child: Text(
                        l.recipientName.isNotEmpty
                            ? l.recipientName[0].toUpperCase()
                            : '?',
                        style: TextStyle(
                            fontSize: 10.sp,
                            fontWeight: FontWeight.w800,
                            color: selected ? Colors.white : AppColors.onSoft),
                      ),
                    ),
                    SizedBox(width: 8.w),
                    Text(l.recipientName,
                        style: TextStyle(
                            fontSize: 13.sp,
                            fontWeight: FontWeight.w700,
                            color: selected ? Colors.white : AppColors.inkSoft)),
                    if (selected) ...[
                      SizedBox(width: 6.w),
                      Icon(Icons.check_circle_rounded, size: 15.sp, color: Colors.white),
                    ],
                  ],
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

/// Compact category selector chip (Medications / Measurements / Activities)
/// reusing the same [ReminderCategory] the patient-facing flow uses so the
/// caregiver's reminder looks and behaves identically once it lands on the
/// recipient's device.
class _CategoryChip extends StatelessWidget {
  const _CategoryChip({required this.category, required this.selected, required this.onTap});

  final ReminderCategory category;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = category.color;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.h),
        decoration: BoxDecoration(
          color: selected ? color : AppColors.card,
          borderRadius: BorderRadius.circular(14.r),
          border: Border.all(color: selected ? color : AppColors.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(category.icon, size: 17.sp, color: selected ? Colors.white : color),
            SizedBox(width: 7.w),
            Text(category.label,
                style: TextStyle(
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w700,
                    color: selected ? Colors.white : AppColors.inkSoft)),
          ],
        ),
      ),
    );
  }
}

/// Two-way pill switch for "Direct assign" vs "Simple note" — replaces the
/// raw [SegmentedButton] with something themed to match the rest of the
/// form's rounded, colored-chip visual language.
class _TogglePill extends StatelessWidget {
  const _TogglePill({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: EdgeInsets.symmetric(vertical: 11.h),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? color : AppColors.card,
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(color: selected ? color : AppColors.line),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 13.sp,
                fontWeight: FontWeight.w700,
                color: selected ? Colors.white : AppColors.muted)),
      ),
    );
  }
}

class _CategoryBanner extends StatelessWidget {
  const _CategoryBanner({required this.category});

  final ReminderCategory category;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
      decoration: BoxDecoration(
        color: category.softColor,
        borderRadius: BorderRadius.circular(16.r),
      ),
      child: Row(
        children: [
          Container(
            width: 40.r,
            height: 40.r,
            decoration: BoxDecoration(
              color: category.color.withValues(alpha: .16),
              borderRadius: BorderRadius.circular(12.r),
            ),
            alignment: Alignment.center,
            child: Icon(category.icon, color: category.color, size: 20.sp),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Text(category.description,
                style: TextStyle(
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w600,
                    color: category.color,
                    height: 1.4)),
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
    return Text(text,
        style: TextStyle(
            fontSize: 11.sp,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
            color: AppColors.muted));
  }
}

class _SuggestionChip extends StatelessWidget {
  const _SuggestionChip({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: EdgeInsets.symmetric(horizontal: 13.w, vertical: 9.h),
        decoration: BoxDecoration(
          color: selected ? color : AppColors.card,
          borderRadius: BorderRadius.circular(99.r),
          border: Border.all(color: selected ? color : AppColors.line),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 12.5.sp,
                fontWeight: FontWeight.w700,
                color: selected ? Colors.white : AppColors.inkSoft)),
      ),
    );
  }
}