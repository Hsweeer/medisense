import 'package:flutter/material.dart';
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
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 90),
                  children: [
                    // Stats header: done · streak · adherence
                    MCard(
                      color: AppColors.soft,
                      border: Border.all(
                          color: AppColors.primary.withValues(alpha: .3)),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 14),
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
                    const SizedBox(height: 16),
                    for (final r in prov.reminders)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _ReminderCard(reminder: r),
                      ),
                  ],
                ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_alert_rounded,
                size: 64, color: AppColors.muted.withValues(alpha: .5)),
            const SizedBox(height: 20),
            Text('No reminders yet',
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            const Text(
              'Create your first reminder to get started.\nGet notified when it\'s time to take your medication.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.muted, height: 1.5),
            ),
            const SizedBox(height: 20),
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
      width: 1,
      height: 30,
      margin: const EdgeInsets.symmetric(horizontal: 4),
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
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppColors.onSoft)),
          const SizedBox(height: 2),
          Text(label,
              style:
                  const TextStyle(fontSize: 11, color: AppColors.onSoft)),
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
      padding: const EdgeInsets.all(14),
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
                  width: 26,
                  height: 26,
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
                        width: 2),
                  ),
                  child: r.taken
                      ? const Icon(Icons.check_rounded,
                          size: 16, color: Colors.white)
                      : isSnoozed
                          ? const Icon(Icons.snooze_rounded,
                              size: 15, color: Colors.white)
                          : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(r.title,
                              style: TextStyle(
                                fontSize: 14.5,
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
                          const SizedBox(width: 6),
                          const MChip('MedAI',
                              icon: Icons.auto_awesome_rounded,
                              background: AppColors.aiSoft,
                              foreground: AppColors.ai),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                        '${r.dose} · ${r.schedule}'
                        '${r.instructions.isEmpty ? '' : ' · ${r.instructions}'}',
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.muted)),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  MChip(r.time,
                      icon: Icons.schedule_rounded,
                      background: AppColors.paper,
                      foreground: AppColors.inkSoft),
                  if (r.streakDays > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('🔥 ${r.streakDays}-day streak',
                          style: const TextStyle(
                              fontSize: 10.5,
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
              padding: const EdgeInsets.only(top: 10),
              child: Row(
                children: [
                  const Icon(Icons.snooze_rounded,
                      size: 15, color: AppColors.warning),
                  const SizedBox(width: 6),
                  Text('Snoozed — ${r.snoozeLabel}',
                      style: const TextStyle(
                          fontSize: 12,
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
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Text('Skipped today — streak reset',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.muted)),
            )
          else if (isPending)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Row(
                children: [
                  _MiniAction(
                      label: 'Take now',
                      color: AppColors.success,
                      onTap: () => prov.take(r)),
                  const SizedBox(width: 8),
                  _MiniAction(
                      label: 'Snooze 10 min',
                      color: AppColors.warning,
                      onTap: () {
                        prov.snooze(r);
                        showToast(context,
                            '${r.title} snoozed — rings again in 10 min');
                      }),
                  const SizedBox(width: 8),
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .1),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: color.withValues(alpha: .35)),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700, color: color)),
      ),
    );
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
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (sheetCtx) => StatefulBuilder(
      builder: (ctx, setSheetState) => Padding(
        padding: EdgeInsets.fromLTRB(
            20, 20, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
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
                          fontSize: 17, fontWeight: FontWeight.w700)),
                ),
                if (reminder != null)
                  IconButton(
                    onPressed: () async {
                      final prov = sheetCtx.read<ReminderProvider>();
                      await prov.remove(reminder);
                      if (sheetCtx.mounted) Navigator.of(sheetCtx).pop();
                    },
                    icon: const Icon(Icons.delete_outline_rounded,
                        color: AppColors.danger),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
                controller: title,
                enabled: reminder == null,
                decoration: const InputDecoration(
                    hintText: 'Medication or habit (e.g. Ibuprofen)')),
            const SizedBox(height: 10),
            TextField(
                controller: dose,
                decoration: const InputDecoration(
                    hintText: 'Dose (e.g. 200 mg · 1 tablet)')),
            const SizedBox(height: 10),
            TextField(
                controller: time,
                decoration:
                    const InputDecoration(hintText: 'Time (e.g. 8:00 PM)')),
            const SizedBox(height: 10),
            TextField(
                controller: instructions,
                decoration: const InputDecoration(
                    hintText: 'Instructions (e.g. after food) — optional')),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
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
            const SizedBox(height: 16),
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
