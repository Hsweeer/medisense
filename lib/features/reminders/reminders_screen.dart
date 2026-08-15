import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/shared_widgets.dart';
import '../../data/models/models.dart';
import '../../providers/reminder_provider.dart';

/// Full reminder system: take / snooze 10 min / skip per dose, streaks,
/// adherence, edit & delete, and MedAI-created reminders tagged violet.
class RemindersScreen extends StatelessWidget {
  const RemindersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<ReminderProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reminders'),
        actions: [
          if (prov.reminders.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(right: 8.w),
              child: TextButton.icon(
                onPressed: () => _confirmClearAll(context, prov),
                icon: Icon(Icons.delete_sweep_rounded,
                    color: AppColors.danger, size: 20.sp),
                label: Text('Clear all',
                    style: TextStyle(
                        color: AppColors.danger,
                        fontWeight: FontWeight.w700,
                        fontSize: 13.sp)),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openAddReminderFlow(context),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add reminder',
            style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: prov.isLoading
          ? const Center(child: CircularProgressIndicator())
          : prov.reminders.isEmpty
          ? _buildEmptyState(context)
          : ListView(
        padding: EdgeInsets.fromLTRB(20.w, 8.h, 20.w, 90.h),
        children: [
          // Stats header: done · streak · adherence
          MCard(
            color: AppColors.soft,
            border: Border.all(
                color: AppColors.primary.withValues(alpha: .3)),
            padding: EdgeInsets.symmetric(
                horizontal: 14.w, vertical: 14.h),
            child: Row(
              children: [
                _Stat(
                    value:
                    '${prov.takenCount}/${prov.reminders.length}',
                    label: 'Done today'),
                _statDivider(),
                _Stat(
                    value: '${prov.bestStreak} days',
                    label: 'Best streak'),
                _statDivider(),
                _Stat(
                    value: '${prov.adherencePct}%',
                    label: 'This week'),
              ],
            ),
          ),
          SizedBox(height: 16.h),
          for (final r in prov.reminders)
            Padding(
              padding: EdgeInsets.only(bottom: 10.h),
              child: _ReminderCard(reminder: r),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(40.r),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_alert_rounded,
                size: 64.sp, color: AppColors.muted.withValues(alpha: .5)),
            SizedBox(height: 20.h),
            Text('No reminders yet',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontSize: 20.sp)),
            SizedBox(height: 8.h),
            Text(
              'Create your first reminder to get started.\nGet notified when it\'s time to take your medication.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.muted, height: 1.5, fontSize: 13.sp),
            ),
            SizedBox(height: 20.h),
            PrimaryButton(
              label: 'Create reminder',
              onPressed: () => _openAddReminderFlow(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statDivider() => Container(
      width: 1.w,
      height: 30.h,
      margin: EdgeInsets.symmetric(horizontal: 4.w),
      color: AppColors.primary.withValues(alpha: .2));

  void _confirmClearAll(BuildContext context, ReminderProvider prov) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20.r)),
        title: Text('Clear all reminders?',
            style: GoogleFonts.sora(fontWeight: FontWeight.w800, fontSize: 18.sp)),
        content: Text(
            'This will permanently delete all your scheduled reminders and alarms.',
            style: TextStyle(fontSize: 14.sp, color: AppColors.muted)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel',
                style:
                TextStyle(color: AppColors.muted, fontWeight: FontWeight.w600, fontSize: 14.sp)),
          ),
          Container(
            margin: EdgeInsets.only(left: 8.w),
            child: FilledButton(
              onPressed: () {
                prov.clearAll();
                Navigator.pop(ctx);
              },
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.danger,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
              ),
              child: Text('Delete all',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.sp)),
            ),
          ),
        ],
      ),
    );
  }

}

void _confirmDeleteDialog(BuildContext context, ReminderProvider prov, Reminder reminder) {
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20.r)),
      title: Text('Delete reminder?',
          style: GoogleFonts.sora(fontWeight: FontWeight.w800, fontSize: 18.sp)),
      content: Text(
          'Are you sure you want to delete "${reminder.title}"? This cannot be undone.',
          style: TextStyle(fontSize: 14.sp, color: AppColors.muted)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text('Cancel',
              style:
              TextStyle(color: AppColors.muted, fontWeight: FontWeight.w600, fontSize: 14.sp)),
        ),
        Container(
          margin: EdgeInsets.only(left: 8.w),
          child: FilledButton(
            onPressed: () {
              prov.remove(reminder);
              Navigator.pop(ctx);
            },
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.danger,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
            ),
            child: Text('Delete',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.sp)),
          ),
        ),
      ],
    ),
  );
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(value,
              style: GoogleFonts.sora(
                  fontSize: 17.sp,
                  fontWeight: FontWeight.w700,
                  color: AppColors.onSoft)),
          SizedBox(height: 2.h),
          Text(label,
              style:
              TextStyle(fontSize: 11.sp, color: AppColors.onSoft)),
        ],
      ),
    );
  }
}

class _ReminderCard extends StatelessWidget {
  const _ReminderCard({required this.reminder});

  final Reminder reminder;

  @override
  Widget build(BuildContext context) {
    final prov = context.read<ReminderProvider>();
    final r = reminder;
    final isPending = r.status == DoseStatus.pending;
    final isSnoozed = r.status == DoseStatus.snoozed;
    final isSkipped = r.status == DoseStatus.skipped;

    return MCard(
      padding: EdgeInsets.all(14.r),
      onTap: () => _showEditSheet(context, reminder: r),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Status circle
              GestureDetector(
                onTap: () => r.taken ? prov.untake(r) : prov.take(r),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 26.r,
                  height: 26.r,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: r.taken
                        ? AppColors.success
                        : isSnoozed
                        ? AppColors.warning
                        : Colors.white,
                    border: Border.all(
                        color: r.taken
                            ? AppColors.success
                            : isSnoozed
                            ? AppColors.warning
                            : AppColors.line,
                        width: 2.w),
                  ),
                  child: r.taken
                      ? Icon(Icons.check_rounded,
                      size: 16.sp, color: Colors.white)
                      : isSnoozed
                      ? Icon(Icons.snooze_rounded,
                      size: 15.sp, color: Colors.white)
                      : null,
                ),
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(r.title,
                              style: TextStyle(
                                fontSize: 14.5.sp,
                                fontWeight: FontWeight.w700,
                                decoration: r.taken || isSkipped
                                    ? TextDecoration.lineThrough
                                    : null,
                                color: r.taken || isSkipped
                                    ? AppColors.muted
                                    : AppColors.ink,
                              )),
                        ),
                        if (r.addedBy == 'MedAI') ...[
                          SizedBox(width: 6.w),
                          const MChip('MedAI',
                              icon: Icons.auto_awesome_rounded,
                              background: AppColors.aiSoft,
                              foreground: AppColors.ai),
                        ],
                      ],
                    ),
                    SizedBox(height: 2.h),
                    Text(
                        '${r.dose} · ${r.schedule}'
                            '${r.instructions.isEmpty ? '' : ' · ${r.instructions}'}',
                        style: TextStyle(
                            fontSize: 12.sp, color: AppColors.muted)),
                    SizedBox(height: 8.h),
                    Row(
                      children: [
                        _QuickAction(
                          icon: Icons.edit_rounded,
                          color: AppColors.primary,
                          onTap: () => _showEditSheet(context, reminder: r),
                        ),
                        SizedBox(width: 10.w),
                        _QuickAction(
                          icon: Icons.delete_outline_rounded,
                          color: AppColors.danger,
                          onTap: () => _confirmDeleteDialog(context, prov, r),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              SizedBox(width: 6.w),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  MChip(r.time,
                      icon: Icons.schedule_rounded,
                      background: AppColors.paper,
                      foreground: AppColors.inkSoft),
                  if (r.streakDays > 0)
                    Padding(
                      padding: EdgeInsets.only(top: 4.h),
                      child: Text('🔥 ${r.streakDays}-day streak',
                          style: TextStyle(
                              fontSize: 10.5.sp,
                              fontWeight: FontWeight.w600,
                              color: AppColors.warning)),
                    ),
                ],
              ),
            ],
          ),
          // Status line / dose actions
          if (isSnoozed)
            Padding(
              padding: EdgeInsets.only(top: 10.h),
              child: Row(
                children: [
                  Icon(Icons.snooze_rounded,
                      size: 15.sp, color: AppColors.warning),
                  SizedBox(width: 6.w),
                  Text('Snoozed — ${r.snoozeLabel}',
                      style: TextStyle(
                          fontSize: 12.sp,
                          fontWeight: FontWeight.w600,
                          color: AppColors.warning)),
                  const Spacer(),
                  _MiniAction(
                      label: 'Take now',
                      color: AppColors.success,
                      onTap: () => prov.take(r)),
                ],
              ),
            )
          else if (isSkipped)
            Padding(
              padding: EdgeInsets.only(top: 10.h),
              child: Text('Skipped today — streak reset',
                  style: TextStyle(
                      fontSize: 12.sp,
                      fontWeight: FontWeight.w600,
                      color: AppColors.muted)),
            )
          else if (isPending)
              Padding(
                padding: EdgeInsets.only(top: 10.h),
                child: Row(
                  children: [
                    _MiniAction(
                        label: 'Take now',
                        color: AppColors.success,
                        onTap: () => prov.take(r)),
                    SizedBox(width: 8.w),
                    _MiniAction(
                        label: 'Snooze 10 min',
                        color: AppColors.warning,
                        onTap: () {
                          prov.snooze(r);
                          showToast(context,
                              '${r.title} snoozed — rings again in 10 min');
                        }),
                    SizedBox(width: 8.w),
                    _MiniAction(
                        label: 'Skip',
                        color: AppColors.muted,
                        onTap: () => prov.skip(r)),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({required this.icon, required this.color, required this.onTap});

  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.all(6.r),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .1),
          borderRadius: BorderRadius.circular(8.r),
        ),
        child: Icon(icon, size: 18.sp, color: color),
      ),
    );
  }
}

class _MiniAction extends StatelessWidget {
  const _MiniAction(
      {required this.label, required this.color, required this.onTap});

  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 7.h),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .1),
          borderRadius: BorderRadius.circular(9.r),
          border: Border.all(color: color.withValues(alpha: .35), width: 1.w),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 12.sp, fontWeight: FontWeight.w700, color: color)),
      ),
    );
  }
}

/// Parses the app's display format ("8:00 PM") back into a [TimeOfDay] so
/// the picker can open already set to the reminder's current time when
/// editing. Returns null (picker falls back to now) if it doesn't match.
TimeOfDay? _parseTimeLabel(String label) {
  final match =
  RegExp(r'^(\d{1,2}):(\d{2})\s*([AaPp][Mm])$').firstMatch(label.trim());
  if (match == null) return null;
  var hour = int.parse(match.group(1)!);
  final minute = int.parse(match.group(2)!);
  final period = match.group(3)!.toUpperCase();
  if (hour < 1 || hour > 12 || minute > 59) return null;
  if (period == 'PM' && hour != 12) hour += 12;
  if (period == 'AM' && hour == 12) hour = 0;
  return TimeOfDay(hour: hour, minute: minute);
}

/// Formats a [TimeOfDay] as "8:00 PM" — fixed 12-hour format so it always
/// matches the app's own display style regardless of device locale.
String _formatTimeOfDay(TimeOfDay t) {
  final hour12 = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
  final minute = t.minute.toString().padLeft(2, '0');
  final period = t.period == DayPeriod.am ? 'AM' : 'PM';
  return '$hour12:$minute $period';
}

/// Shared themed time picker — returns the picked [TimeOfDay] directly so
/// callers that manage a list of times (rather than a single controller)
/// can use it too.
Future<TimeOfDay?> _pickTimeValue(BuildContext context,
    {TimeOfDay? initial}) async {
  return showTimePicker(
    context: context,
    initialTime: initial ?? TimeOfDay.now(),
    builder: (pickerCtx, child) {
      final base = Theme.of(pickerCtx);
      return Theme(
        data: base.copyWith(
          colorScheme: base.colorScheme.copyWith(
            primary: AppColors.primary,
            onPrimary: Colors.white,
            surface: AppColors.card,
            onSurface: AppColors.ink,
          ),
          timePickerTheme: TimePickerThemeData(
            backgroundColor: AppColors.card,
            hourMinuteColor: WidgetStateColor.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? AppColors.primary.withValues(alpha: .12)
                : AppColors.paper),
            hourMinuteTextColor: WidgetStateColor.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? AppColors.primary
                : AppColors.ink),
            dayPeriodColor: WidgetStateColor.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? AppColors.primary.withValues(alpha: .12)
                : AppColors.paper),
            dayPeriodTextColor: WidgetStateColor.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? AppColors.primary
                : AppColors.ink),
            dialBackgroundColor: AppColors.paper,
            dialHandColor: AppColors.primary,
            entryModeIconColor: AppColors.primary,
            hourMinuteShape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            dayPeriodShape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: AppColors.line)),
            shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          ),
          textButtonTheme: TextButtonThemeData(
            style: TextButton.styleFrom(foregroundColor: AppColors.primary),
          ),
        ),
        child: child!,
      );
    },
  );
}

/// Add (reminder == null) or edit an existing reminder.
/// Opens the single add/edit bottom sheet — name, dose, time, schedule —
/// same sheet used for editing, no multi-step onboarding wizard.
void _openAddReminderFlow(BuildContext context) {
  _showEditSheet(context);
}

void _showEditSheet(BuildContext context, {Reminder? reminder}) {
  final title = TextEditingController(text: reminder?.title ?? '');
  final dose = TextEditingController(text: reminder?.dose ?? '');
  // A single card can carry more than one dose time a day (e.g. "8:00 AM,
  // 2:00 PM, 9:00 PM" for a 3x-daily medicine) — each becomes its own
  // native alarm under the same reminder, so the user never has to create
  // a separate card just to add another time for the same medication.
  final List<String> times = (reminder?.time ?? '')
      .split(',')
      .map((t) => t.trim())
      .where((t) => t.isNotEmpty)
      .toList();
  final instructions =
  TextEditingController(text: reminder?.instructions ?? '');
  var schedule = reminder?.schedule ?? 'Daily';
  const scheduleOptions = ['Daily', 'Weekdays', 'Mon · Wed · Fri', 'Custom'];

  // Handle parsing existing custom schedule
  Set<int> selectedDays = {};
  if (schedule == 'Weekdays') {
    selectedDays = {1, 2, 3, 4, 5};
  } else if (schedule == 'Mon · Wed · Fri') {
    selectedDays = {1, 3, 5};
  } else if (schedule != 'Daily') {
    // Check if it's a custom list like "Mon · Tue"
    final parts = schedule.split(' · ');
    const dayMap = {
      'Mon': 1,
      'Tue': 2,
      'Wed': 3,
      'Thu': 4,
      'Fri': 5,
      'Sat': 6,
      'Sun': 7
    };
    for (var p in parts) {
      if (dayMap.containsKey(p)) selectedDays.add(dayMap[p]!);
    }
    if (selectedDays.isNotEmpty) schedule = 'Custom';
  }

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.card,
    useSafeArea: true, // Make it larger/taller
    shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32.r))),
    builder: (sheetCtx) => StatefulBuilder(
      builder: (ctx, setSheetState) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(ctx).size.height * 0.85,
        ),
        padding: EdgeInsets.fromLTRB(
            24.w, 24.h, 24.w, (24.h + MediaQuery.of(ctx).viewInsets.bottom)),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                        reminder == null ? 'Add Reminder' : 'Edit Reminder',
                        style: GoogleFonts.sora(
                            fontSize: 20.sp, fontWeight: FontWeight.w800)),
                  ),
                  if (reminder != null)
                    IconButton(
                      onPressed: () async {
                        final prov = sheetCtx.read<ReminderProvider>();
                        await prov.remove(reminder);
                        if (sheetCtx.mounted) Navigator.of(sheetCtx).pop();
                      },
                      icon: Icon(Icons.delete_outline_rounded,
                          color: AppColors.danger, size: 26.sp),
                    ),
                ],
              ),
              SizedBox(height: 20.h),
              Text('WHAT & HOW MUCH',
                  style: TextStyle(
                      fontSize: 11.sp,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                      color: AppColors.muted)),
              SizedBox(height: 10.h),
              TextField(
                  controller: title,
                  enabled: reminder == null,
                  style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600),
                  decoration: InputDecoration(
                      hintText: 'Medication name',
                      prefixIcon: Icon(Icons.medication_rounded, size: 22.sp))),
              SizedBox(height: 12.h),
              TextField(
                  controller: dose,
                  style: TextStyle(fontSize: 16.sp),
                  decoration: InputDecoration(
                      hintText: 'Dose (e.g. 1 tablet, 500mg)',
                      prefixIcon: Icon(Icons.fitness_center_rounded, size: 22.sp))),
              SizedBox(height: 24.h),
              Text('WHEN',
                  style: TextStyle(
                      fontSize: 11.sp,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                      color: AppColors.muted)),
              SizedBox(height: 10.h),
              Wrap(
                spacing: 8.w,
                runSpacing: 8.h,
                children: [
                  for (final t in times)
                    Container(
                      padding: EdgeInsets.symmetric(
                          horizontal: 12.w, vertical: 9.h),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: .10),
                        borderRadius: BorderRadius.circular(12.r),
                        border: Border.all(
                            color: AppColors.primary.withValues(alpha: .3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.access_time_filled_rounded,
                              color: AppColors.primary, size: 16.sp),
                          SizedBox(width: 6.w),
                          Text(t,
                              style: TextStyle(
                                  fontSize: 14.sp,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.ink)),
                          SizedBox(width: 4.w),
                          GestureDetector(
                            onTap: () {
                              // Keep at least one time — an alarm card with
                              // zero times has nothing to schedule.
                              if (times.length > 1) {
                                setSheetState(() => times.remove(t));
                              }
                            },
                            child: Icon(Icons.close_rounded,
                                size: 16.sp, color: AppColors.muted),
                          ),
                        ],
                      ),
                    ),
                  GestureDetector(
                    onTap: () async {
                      final picked = await _pickTimeValue(ctx);
                      if (picked == null) return;
                      final label = _formatTimeOfDay(picked);
                      if (!times.contains(label)) {
                        setSheetState(() {
                          times.add(label);
                          int minutesOf(String s) {
                            final t = _parseTimeLabel(s) ?? TimeOfDay.now();
                            return t.hour * 60 + t.minute;
                          }
                          times.sort(
                                  (a, b) => minutesOf(a).compareTo(minutesOf(b)));
                        });
                      }
                    },
                    child: Container(
                      padding: EdgeInsets.symmetric(
                          horizontal: 14.w, vertical: 9.h),
                      decoration: BoxDecoration(
                        color: AppColors.paper,
                        borderRadius: BorderRadius.circular(12.r),
                        border: Border.all(
                            color: AppColors.line, style: BorderStyle.solid),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.add_rounded,
                              size: 16.sp, color: AppColors.primary),
                          SizedBox(width: 4.w),
                          Text('Add time',
                              style: TextStyle(
                                  fontSize: 13.sp,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.primary)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 6.h),
              Text('Add every time this medicine is due — one card handles all of them.',
                  style: TextStyle(fontSize: 11.5.sp, color: AppColors.muted)),
              SizedBox(height: 24.h),
              Text('SCHEDULE',
                  style: TextStyle(
                      fontSize: 11.sp,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                      color: AppColors.muted)),
              SizedBox(height: 12.h),
              Wrap(
                spacing: 8.w,
                runSpacing: 10.h,
                children: [
                  for (final s in scheduleOptions)
                    GestureDetector(
                      onTap: () {
                        setSheetState(() {
                          schedule = s;
                          if (s == 'Daily') selectedDays = {};
                          if (s == 'Weekdays') selectedDays = {1, 2, 3, 4, 5};
                          if (s == 'Mon · Wed · Fri') selectedDays = {1, 3, 5};
                        });
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: EdgeInsets.symmetric(
                            horizontal: 16.w, vertical: 10.h),
                        decoration: BoxDecoration(
                          color: s == schedule
                              ? AppColors.primary
                              : AppColors.paper,
                          borderRadius: BorderRadius.circular(12.r),
                          border: Border.all(
                            color: s == schedule
                                ? AppColors.primary
                                : AppColors.line,
                          ),
                        ),
                        child: Text(s,
                            style: TextStyle(
                                fontSize: 13.sp,
                                fontWeight: FontWeight.w700,
                                color: s == schedule
                                    ? Colors.white
                                    : AppColors.muted)),
                      ),
                    ),
                ],
              ),
              if (schedule == 'Custom') ...[
                SizedBox(height: 20.h),
                Container(
                  padding: EdgeInsets.all(12.r),
                  decoration: BoxDecoration(
                    color: AppColors.soft,
                    borderRadius: BorderRadius.circular(16.r),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      for (int i = 1; i <= 7; i++)
                        _DayButton(
                          day: i,
                          isSelected: selectedDays.contains(i),
                          onTap: () {
                            setSheetState(() {
                              if (selectedDays.contains(i)) {
                                if (selectedDays.length > 1) {
                                  selectedDays.remove(i);
                                }
                              } else {
                                selectedDays.add(i);
                              }
                            });
                          },
                        ),
                    ],
                  ),
                ),
              ],
              SizedBox(height: 24.h),
              TextField(
                  controller: instructions,
                  style: TextStyle(fontSize: 15.sp),
                  decoration: InputDecoration(
                      hintText: 'Additional instructions (optional)',
                      prefixIcon: Icon(Icons.notes_rounded, size: 22.sp))),
              SizedBox(height: 32.h),
              PrimaryButton(
                label: reminder == null ? 'Set Reminder' : 'Update Reminder',
                onPressed: () async {
                  final prov = sheetCtx.read<ReminderProvider>();
                  String finalSchedule = schedule;
                  if (schedule == 'Custom') {
                    final sorted = selectedDays.toList()..sort();
                    const dayNames = [
                      '',
                      'Mon',
                      'Tue',
                      'Wed',
                      'Thu',
                      'Fri',
                      'Sat',
                      'Sun'
                    ];
                    finalSchedule =
                        sorted.map((d) => dayNames[d]).join(' · ');
                  }

                  final joinedTimes =
                  times.isEmpty ? '9:00 AM' : times.join(', ');

                  if (reminder == null) {
                    if (title.text.trim().isEmpty) return;
                    await prov.add(Reminder(
                      title: title.text.trim(),
                      dose: dose.text.trim().isEmpty
                          ? '1 dose'
                          : dose.text.trim(),
                      time: joinedTimes,
                      schedule: finalSchedule,
                      instructions: instructions.text.trim(),
                    ));
                  } else {
                    await prov.update(reminder,
                        dose: dose.text.trim(),
                        time: joinedTimes,
                        schedule: finalSchedule,
                        instructions: instructions.text.trim());
                  }
                  if (sheetCtx.mounted) Navigator.of(sheetCtx).pop();
                },
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _DayButton extends StatelessWidget {
  final int day;
  final bool isSelected;
  final VoidCallback onTap;

  const _DayButton({
    required this.day,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const dayNames = ['', 'M', 'T', 'W', 'T', 'F', 'S', 'S'];
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 38.r,
        height: 38.r,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : Colors.white,
          shape: BoxShape.circle,
          boxShadow: isSelected
              ? [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.3),
              blurRadius: 8.r,
              offset: Offset(0, 4.h),
            )
          ]
              : null,
        ),
        child: Text(
          dayNames[day],
          style: TextStyle(
            fontSize: 14.sp,
            fontWeight: FontWeight.w800,
            color: isSelected ? Colors.white : AppColors.muted,
          ),
        ),
      ),
    );
  }
}
