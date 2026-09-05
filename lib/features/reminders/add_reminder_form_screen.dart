import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/shared_widgets.dart';
import '../../data/models/models.dart';
import '../../providers/reminder_provider.dart';
import 'custom_suggestions_store.dart';
import 'reminder_form_helpers.dart';

/// Full-screen version of the add-reminder flow, opened from
/// [AddReminderCategoryScreen]. Same fields as the quick edit bottom sheet
/// (name, dose/value, time(s), schedule, notes) but rendered as its own
/// page, with category-aware suggestion chips (the app's own presets plus
/// anything the user has added themselves) so the user can tap a preset
/// or type something entirely their own.
class AddReminderFormScreen extends StatefulWidget {
  const AddReminderFormScreen({super.key, required this.category});

  final ReminderCategory category;

  @override
  State<AddReminderFormScreen> createState() => _AddReminderFormScreenState();
}

class _AddReminderFormScreenState extends State<AddReminderFormScreen> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _value = TextEditingController();
  final TextEditingController _provider = TextEditingController();
  final TextEditingController _instructions = TextEditingController();

  final List<String> _times = [];
  String _schedule = 'Daily';
  Set<int> _selectedDays = {};
  DateTime? _onDate;
  bool _saving = false;

  List<String> _customSuggestions = [];

  static const _scheduleOptions = [
    'Daily',
    'Weekdays',
    'Mon · Wed · Fri',
    'Custom',
    'On a date',
  ];

  ReminderCategory get category => widget.category;

  List<String> get _allSuggestions => [
    ...category.suggestions,
    ..._customSuggestions,
  ];

  @override
  void initState() {
    super.initState();
    _loadCustomSuggestions();
  }

  Future<void> _loadCustomSuggestions() async {
    final saved = await CustomSuggestionsStore.instance.load(category);
    if (mounted) setState(() => _customSuggestions = saved);
  }

  @override
  void dispose() {
    _name.dispose();
    _value.dispose();
    _provider.dispose();
    _instructions.dispose();
    super.dispose();
  }

  Future<void> _pickOnDate() async {
    final picked = await pickAppointmentDate(context, initial: _onDate);
    if (picked == null) return;
    setState(() {
      _schedule = 'On a date';
      _onDate = picked;
      _selectedDays = {};
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    final name = _name.text.trim();
    if (name.isEmpty) {
      showToast(context, 'Please enter a name first', color: AppColors.danger);
      return;
    }
    if (_schedule == 'On a date' && _onDate == null) {
      showToast(context, 'Please pick a date', color: AppColors.danger);
      return;
    }

    setState(() => _saving = true);

    String finalSchedule = _schedule;
    if (_schedule == 'Custom') {
      final sorted = _selectedDays.toList()..sort();
      const dayNames = ['', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      finalSchedule = sorted.map((d) => dayNames[d]).join(' · ');
    } else if (_schedule == 'On a date' && _onDate != null) {
      finalSchedule = formatAppointmentDate(_onDate!);
    }
    final joinedTimes = _times.isEmpty ? '9:00 AM' : _times.join(', ');

    final prov = context.read<ReminderProvider>();
    await prov.add(
      Reminder(
        title: name,
        dose: category.hasProviderField
            ? category.defaultValue
            : (_value.text.trim().isEmpty
                  ? category.defaultValue
                  : _value.text.trim()),
        time: joinedTimes,
        schedule: finalSchedule,
        instructions: _instructions.text.trim(),
        groupType: category.hasProviderField ? 'checkup' : 'medicine',
        location: category.hasProviderField ? _value.text.trim() : '',
        provider: category.hasProviderField ? _provider.text.trim() : '',
      ),
    );

    if (!mounted) return;
    setState(() => _saving = false);
    showToast(context, '$name added to your reminders', color: category.color);
    // Pop with a result so the category picker above us can close too and
    // the reminders list (already watching the provider) reflects the
    // brand-new card immediately.
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final accent = category.color;

    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        backgroundColor: AppColors.paper,
        elevation: 0,
        title: Text(
          'Add ${category.singularLabel}',
          style: GoogleFonts.sora(
            fontSize: 17.sp,
            fontWeight: FontWeight.w800,
            color: AppColors.ink,
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
          physics: category.hasProviderField
              ? const NeverScrollableScrollPhysics()
              : null,
          padding: EdgeInsets.fromLTRB(20.w, 4.h, 20.w, 40.h),
          children: [
            _CategoryBanner(category: category),
            SizedBox(height: 26.h),
            Row(
              children: [
                Expanded(child: _SectionLabel(category.nameSectionLabel)),
              ],
            ),
            SizedBox(height: 10.h),
            SizedBox(
              height: 38.h,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                itemCount: _allSuggestions.length,
                separatorBuilder: (_, _) => SizedBox(width: 8.w),
                itemBuilder: (ctx, i) {
                  final s = _allSuggestions[i];
                  return _SuggestionChip(
                    label: s,
                    selected: _name.text.trim() == s,
                    color: accent,
                    onTap: () => setState(() => _name.text = s),
                  );
                },
              ),
            ),
            SizedBox(height: 6.h),
            Text(
              'Tap a suggestion or type below.',
              style: TextStyle(fontSize: 11.5.sp, color: AppColors.muted),
            ),
            SizedBox(height: 12.h),
            TextField(
              controller: _name,
              style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: category.nameFieldHint,
                prefixIcon: Icon(category.icon, size: 22.sp, color: accent),
              ),
            ),
            SizedBox(height: 12.h),
            TextField(
              controller: _value,
              style: TextStyle(fontSize: 15.sp),
              decoration: InputDecoration(
                hintText: category.valueFieldHint,
                prefixIcon: Icon(
                  category.hasProviderField
                      ? Icons.location_on_rounded
                      : Icons.fitness_center_rounded,
                  size: 22.sp,
                ),
              ),
            ),
            if (category.hasProviderField) ...[
              SizedBox(height: 12.h),
              TextField(
                controller: _provider,
                style: TextStyle(fontSize: 15.sp),
                decoration: InputDecoration(
                  hintText: category.providerFieldHint,
                  prefixIcon: Icon(Icons.badge_rounded, size: 22.sp),
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
                    padding: EdgeInsets.symmetric(
                      horizontal: 12.w,
                      vertical: 9.h,
                    ),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: .10),
                      borderRadius: BorderRadius.circular(12.r),
                      border: Border.all(color: accent.withValues(alpha: .3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.access_time_filled_rounded,
                          color: accent,
                          size: 16.sp,
                        ),
                        SizedBox(width: 6.w),
                        Text(
                          t,
                          style: TextStyle(
                            fontSize: 14.sp,
                            fontWeight: FontWeight.w700,
                            color: AppColors.ink,
                          ),
                        ),
                        SizedBox(width: 4.w),
                        GestureDetector(
                          onTap: () {
                            if (_times.length > 1) {
                              setState(() => _times.remove(t));
                            }
                          },
                          child: Icon(
                            Icons.close_rounded,
                            size: 16.sp,
                            color: AppColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                GestureDetector(
                  onTap: () async {
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

                        _times.sort(
                          (a, b) => minutesOf(a).compareTo(minutesOf(b)),
                        );
                      });
                    }
                  },
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: 14.w,
                      vertical: 9.h,
                    ),
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
                        Text(
                          'Add time',
                          style: TextStyle(
                            fontSize: 13.sp,
                            fontWeight: FontWeight.w700,
                            color: accent,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 6.h),
            Text(
              'Add every time this is due — one reminder handles all of them.',
              style: TextStyle(fontSize: 11.5.sp, color: AppColors.muted),
            ),
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
                      if (s == 'On a date') {
                        _pickOnDate();
                        return;
                      }
                      setState(() {
                        _schedule = s;
                        _onDate = null;
                        if (s == 'Daily') _selectedDays = {};
                        if (s == 'Weekdays') _selectedDays = {1, 2, 3, 4, 5};
                        if (s == 'Mon · Wed · Fri') _selectedDays = {1, 3, 5};
                      });
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: EdgeInsets.symmetric(
                        horizontal: 16.w,
                        vertical: 10.h,
                      ),
                      decoration: BoxDecoration(
                        color: s == _schedule ? accent : AppColors.card,
                        borderRadius: BorderRadius.circular(12.r),
                        border: Border.all(
                          color: s == _schedule ? accent : AppColors.line,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (s == 'On a date') ...[
                            Icon(
                              Icons.event_rounded,
                              size: 15.sp,
                              color: s == _schedule
                                  ? Colors.white
                                  : AppColors.muted,
                            ),
                            SizedBox(width: 5.w),
                          ],
                          Text(
                            s == 'On a date' && _onDate != null
                                ? formatAppointmentDate(_onDate!)
                                : s,
                            style: TextStyle(
                              fontSize: 13.sp,
                              fontWeight: FontWeight.w700,
                              color: s == _schedule
                                  ? Colors.white
                                  : AppColors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            if (_schedule == 'Custom') ...[
              SizedBox(height: 20.h),
              Container(
                padding: EdgeInsets.all(12.r),
                decoration: BoxDecoration(
                  color: category.softColor,
                  borderRadius: BorderRadius.circular(16.r),
                ),
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
                              if (_selectedDays.length > 1) {
                                _selectedDays.remove(i);
                              }
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
            if (_schedule == 'On a date') ...[
              SizedBox(height: 6.h),
              Text(
                _onDate == null
                    ? 'Tap "On a date" again to pick a date.'
                    : 'This reminder is set for ${formatAppointmentDate(_onDate!)} only.',
                style: TextStyle(fontSize: 11.5.sp, color: AppColors.muted),
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
    );
  }
}

/// Small colored banner at the top of the form reinforcing which category
/// the user is in — a light touch of polish so the full-screen page still
/// feels connected to the card they tapped.
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
            child: Text(
              category.description,
              style: TextStyle(
                fontSize: 12.sp,
                fontWeight: FontWeight.w600,
                color: category.color,
                height: 1.4,
              ),
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
    return Text(
      text,
      style: TextStyle(
        fontSize: 11.sp,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.2,
        color: AppColors.muted,
      ),
    );
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
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5.sp,
            fontWeight: FontWeight.w700,
            color: selected ? Colors.white : AppColors.inkSoft,
          ),
        ),
      ),
    );
  }
}
