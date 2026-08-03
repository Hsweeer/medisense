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
      appBar: AppBar(title: const Text('Reminders')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showEditSheet(context),
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
              onPressed: () => _showEditSheet(context),
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

/// Opens the app-themed time picker and writes the result straight into
/// [controller] in the app's fixed "8:00 PM" format.
Future<void> _pickTime(
    BuildContext context, TextEditingController controller) async {
  final initial = _parseTimeLabel(controller.text) ?? TimeOfDay.now();
  final picked = await showTimePicker(
    context: context,
    initialTime: initial,
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
  if (picked != null) {
    controller.text = _formatTimeOfDay(picked);
  }
}

/// Add (reminder == null) or edit an existing reminder.
void _showEditSheet(BuildContext context, {Reminder? reminder}) {
  final title = TextEditingController(text: reminder?.title ?? '');
  final dose = TextEditingController(text: reminder?.dose ?? '');
  final time = TextEditingController(text: reminder?.time ?? '');
  final instructions =
      TextEditingController(text: reminder?.instructions ?? '');
  var schedule = reminder?.schedule ?? 'Daily';
  const scheduleOptions = ['Daily', 'Weekdays', 'Mon · Wed · Fri', 'Custom'];
  if (!scheduleOptions.contains(schedule)) schedule = 'Custom';

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.card,
    shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24.r))),
    builder: (sheetCtx) => StatefulBuilder(
      builder: (ctx, setSheetState) => Padding(
        padding: EdgeInsets.fromLTRB(
            20.w, 20.h, 20.w, (20.h + MediaQuery.of(ctx).viewInsets.bottom)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                      reminder == null ? 'New reminder' : 'Edit reminder',
                      style: GoogleFonts.sora(
                          fontSize: 17.sp, fontWeight: FontWeight.w700)),
                ),
                if (reminder != null)
                  IconButton(
                    onPressed: () async {
                      final prov = sheetCtx.read<ReminderProvider>();
                      await prov.remove(reminder);
                      if (sheetCtx.mounted) Navigator.of(sheetCtx).pop();
                    },
                    icon: Icon(Icons.delete_outline_rounded,
                        color: AppColors.danger, size: 24.sp),
                  ),
              ],
            ),
            SizedBox(height: 12.h),
            TextField(
                controller: title,
                enabled: reminder == null,
                style: TextStyle(fontSize: 15.sp),
                decoration: InputDecoration(
                    hintText: 'Medication or habit (e.g. Ibuprofen)',
                    hintStyle: TextStyle(fontSize: 14.sp))),
            SizedBox(height: 10.h),
            TextField(
                controller: dose,
                style: TextStyle(fontSize: 15.sp),
                decoration: InputDecoration(
                    hintText: 'Dose (e.g. 200 mg · 1 tablet)',
                    hintStyle: TextStyle(fontSize: 14.sp))),
            SizedBox(height: 10.h),
            // Time — tap to open the native time picker. Read-only so the
            // keyboard never shows and the value can never be typed wrong.
            TextField(
              controller: time,
              readOnly: true,
              showCursor: false,
              style: TextStyle(fontSize: 15.sp),
              onTap: () => _pickTime(ctx, time),
              decoration: InputDecoration(
                hintText: 'Select time',
                hintStyle: TextStyle(fontSize: 14.sp),
                prefixIcon:
                    Icon(Icons.access_time_rounded, color: AppColors.muted, size: 20.sp),
                suffixIcon:
                    Icon(Icons.expand_more_rounded, color: AppColors.muted, size: 20.sp),
              ),
            ),
            SizedBox(height: 10.h),
            TextField(
                controller: instructions,
                style: TextStyle(fontSize: 15.sp),
                decoration: InputDecoration(
                    hintText: 'Instructions (e.g. after food) — optional',
                    hintStyle: TextStyle(fontSize: 14.sp))),
            SizedBox(height: 12.h),
            Wrap(
              spacing: 8.w,
              runSpacing: 8.h,
              children: [
                for (final s in scheduleOptions)
                  MChip(s,
                      background:
                          s == schedule ? AppColors.primary : AppColors.paper,
                      foreground:
                          s == schedule ? Colors.white : AppColors.muted,
                      onTap: () => setSheetState(() => schedule = s)),
              ],
            ),
            SizedBox(height: 16.h),
            PrimaryButton(
              label: reminder == null ? 'Save reminder' : 'Save changes',
              onPressed: () async {
                final prov = sheetCtx.read<ReminderProvider>();
                if (reminder == null) {
                  if (title.text.trim().isEmpty) return;
                  await prov.add(Reminder(
                    title: title.text.trim(),
                    dose: dose.text.trim().isEmpty
                        ? '1 dose'
                        : dose.text.trim(),
                    time: time.text.trim().isEmpty
                        ? '9:00 AM'
                        : time.text.trim(),
                    schedule: schedule,
                    instructions: instructions.text.trim(),
                  ));
                } else {
                  await prov.update(reminder,
                      dose: dose.text.trim(),
                      time: time.text.trim(),
                      schedule: schedule,
                      instructions: instructions.text.trim());
                }
                if (sheetCtx.mounted) Navigator.of(sheetCtx).pop();
              },
            ),
          ],
        ),
      ),
    ),
  );
}
