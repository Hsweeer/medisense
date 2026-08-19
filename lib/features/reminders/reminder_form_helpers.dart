import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../core/theme/app_colors.dart';

/// The three categories offered when creating a new reminder — mirrors the
/// app's own "Medications / Measurements / Activities" routine setup, each
/// themed with one of MediSense's existing accent colors so nothing feels
/// bolted on.
enum ReminderCategory { medication, measurement, activity }

extension ReminderCategoryX on ReminderCategory {
  String get label => switch (this) {
    ReminderCategory.medication => 'Medications',
    ReminderCategory.measurement => 'Measurements',
    ReminderCategory.activity => 'Activities',
  };

  String get singularLabel => switch (this) {
    ReminderCategory.medication => 'Medication',
    ReminderCategory.measurement => 'Measurement',
    ReminderCategory.activity => 'Activity',
  };

  String get description => switch (this) {
    ReminderCategory.medication =>
    'Add medications to your treatment plan to get reminders and track your intakes.',
    ReminderCategory.measurement =>
    'Set up reminders to log health data like blood pressure, weight, or blood sugar.',
    ReminderCategory.activity =>
    'Set up reminders for daily habits such as walking, drinking water, or stretching.',
  };

  IconData get icon => switch (this) {
    ReminderCategory.medication => Icons.medication_rounded,
    ReminderCategory.measurement => Icons.monitor_heart_rounded,
    ReminderCategory.activity => Icons.directions_walk_rounded,
  };

  /// Brand accent used for this category — reuses the app's existing
  /// palette (teal / violet / amber) instead of introducing new colors.
  Color get color => switch (this) {
    ReminderCategory.medication => AppColors.primary,
    ReminderCategory.measurement => AppColors.ai,
    ReminderCategory.activity => AppColors.warning,
  };

  Color get softColor => switch (this) {
    ReminderCategory.medication => AppColors.soft,
    ReminderCategory.measurement => AppColors.aiSoft,
    ReminderCategory.activity => AppColors.warningSoft,
  };

  String get nameSectionLabel => switch (this) {
    ReminderCategory.medication => 'MEDICATION',
    ReminderCategory.measurement => 'MEASUREMENT TYPE',
    ReminderCategory.activity => 'ACTIVITY',
  };

  String get nameFieldHint => switch (this) {
    ReminderCategory.medication => 'Medication name',
    ReminderCategory.measurement => 'e.g. Blood Pressure, Weight',
    ReminderCategory.activity => 'e.g. Walking, Stretching',
  };

  String get valueFieldHint => switch (this) {
    ReminderCategory.medication => 'Dose (e.g. 1 tablet, 500mg)',
    ReminderCategory.measurement => 'Target / notes (e.g. under 120/80)',
    ReminderCategory.activity => 'Goal (e.g. 30 minutes, 2,000 steps)',
  };

  String get defaultValue => switch (this) {
    ReminderCategory.medication => '1 dose',
    ReminderCategory.measurement => 'Log reading',
    ReminderCategory.activity => 'Complete activity',
  };

  /// Quick-pick chips — the user can tap one to fill the name field, or
  /// ignore them and type their own in the text field right below.
  List<String> get suggestions => switch (this) {
    ReminderCategory.medication => const [
      'Paracetamol',
      'Ibuprofen',
      'Aspirin',
      'Amoxicillin',
      'Metformin',
      'Atorvastatin',
      'Omeprazole',
      'Vitamin D3',
    ],
    ReminderCategory.measurement => const [
      'Blood Pressure',
      'Weight',
      'Blood Sugar',
      'Heart Rate',
      'Temperature',
      'Oxygen Saturation',
      'Cholesterol',
      'Steps',
    ],
    ReminderCategory.activity => const [
      'Walking',
      'Drinking Water',
      'Stretching',
      'Exercise',
      'Yoga',
      'Meditation',
      'Cycling',
      'Sleep',
    ],
  };
}

/// Parses the app's display format ("8:00 PM") back into a [TimeOfDay] so
/// the picker can open already set to the reminder's current time when
/// editing. Returns null (picker falls back to now) if it doesn't match.
TimeOfDay? parseTimeLabel(String label) {
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
String formatTimeOfDay(TimeOfDay t) {
  final hour12 = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
  final minute = t.minute.toString().padLeft(2, '0');
  final period = t.period == DayPeriod.am ? 'AM' : 'PM';
  return '$hour12:$minute $period';
}

/// Shared themed time picker — returns the picked [TimeOfDay] directly so
/// callers that manage a list of times (rather than a single controller)
/// can use it too.
Future<TimeOfDay?> pickTimeValue(BuildContext context,
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
            hourMinuteShape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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

/// Single day-of-week circle used by the "Custom" schedule picker.
/// Accepts an optional [color] so it can match whichever category (or the
/// default teal brand) is driving the surrounding form.
class DayButton extends StatelessWidget {
  final int day;
  final bool isSelected;
  final VoidCallback onTap;
  final Color color;

  const DayButton({
    super.key,
    required this.day,
    required this.isSelected,
    required this.onTap,
    this.color = AppColors.primary,
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
          color: isSelected ? color : Colors.white,
          shape: BoxShape.circle,
          boxShadow: isSelected
              ? [
            BoxShadow(
              color: color.withValues(alpha: 0.3),
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