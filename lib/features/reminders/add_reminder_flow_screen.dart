import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/shared_widgets.dart';
import '../../data/models/models.dart';
import '../../providers/reminder_provider.dart';

/// Entry point for the FAB → "Add reminder" flow.
/// Shows 3 categories (Medications / Measurements / Activities); tapping a
/// category's "+" opens its own multi-step wizard. Everything saved here is
/// persisted straight to Firestore under the current user via
/// [ReminderProvider.add] — the same path the old edit sheet uses.
class AddReminderFlowScreen extends StatefulWidget {
  const AddReminderFlowScreen({super.key});

  @override
  State<AddReminderFlowScreen> createState() => _AddReminderFlowScreenState();
}

class _AddReminderFlowScreenState extends State<AddReminderFlowScreen> {
  final Map<String, int> _added = {
    'medication': 0,
    'measurement': 0,
    'activity': 0,
  };

  int get _totalAdded => _added.values.fold(0, (a, b) => a + b);

  Future<void> _openCategory(String category) async {
    Widget wizard;
    switch (category) {
      case 'medication':
        wizard = const _MedicationWizard();
        break;
      case 'measurement':
        wizard = const _CategoryPickerWizard(category: 'measurement');
        break;
      default:
        wizard = const _CategoryPickerWizard(category: 'activity');
    }
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => wizard),
    );
    if (saved == true) {
      setState(() => _added[category] = (_added[category] ?? 0) + 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final progress = (_totalAdded / 3).clamp(0.0, 1.0);

    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        title: const Text("Let's set up your routine"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, _totalAdded > 0),
            child: Text('Skip',
                style: TextStyle(
                    color: AppColors.muted,
                    fontWeight: FontWeight.w700,
                    fontSize: 14.sp)),
          ),
        ],
      ),
      body: Padding(
        padding: EdgeInsets.fromLTRB(20.w, 8.h, 20.w, 20.h),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Start by adding from any of the categories below.',
                style: TextStyle(fontSize: 13.5.sp, color: AppColors.muted)),
            SizedBox(height: 16.h),
            ClipRRect(
              borderRadius: BorderRadius.circular(20.r),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 6.h,
                backgroundColor: AppColors.line,
                valueColor:
                const AlwaysStoppedAnimation<Color>(AppColors.primary),
              ),
            ),
            SizedBox(height: 20.h),
            Expanded(
              child: ListView(
                children: [
                  _CategoryCard(
                    icon: Icons.medication_rounded,
                    iconBg: AppColors.soft,
                    iconColor: AppColors.primary,
                    title: 'Medications',
                    description:
                    'Add medications to your treatment plan to get reminders and track your intakes.',
                    count: _added['medication']!,
                    onTap: () => _openCategory('medication'),
                  ),
                  SizedBox(height: 14.h),
                  _CategoryCard(
                    icon: Icons.monitor_heart_rounded,
                    iconBg: AppColors.aiSoft,
                    iconColor: AppColors.ai,
                    title: 'Measurements',
                    description:
                    'Set up reminders to log health data like blood pressure, weight, or blood sugar.',
                    count: _added['measurement']!,
                    onTap: () => _openCategory('measurement'),
                  ),
                  SizedBox(height: 14.h),
                  _CategoryCard(
                    icon: Icons.directions_walk_rounded,
                    iconBg: AppColors.successSoft,
                    iconColor: AppColors.success,
                    title: 'Activities',
                    description:
                    'Set up reminders for daily habits such as walking, drinking water, or stretching.',
                    count: _added['activity']!,
                    onTap: () => _openCategory('activity'),
                  ),
                ],
              ),
            ),
            SizedBox(height: 8.h),
            PrimaryButton(
              label: _totalAdded > 0 ? 'All set!' : 'Skip for now',
              onPressed: () => Navigator.pop(context, _totalAdded > 0),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    required this.description,
    required this.count,
    required this.onTap,
  });

  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final String description;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedRRectPainter(
        color: count > 0
            ? AppColors.primary.withValues(alpha: .45)
            : AppColors.line,
        radius: 18.r,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18.r),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.all(16.r),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52.r,
                height: 52.r,
                decoration:
                BoxDecoration(color: iconBg, shape: BoxShape.circle),
                child: Icon(icon, color: iconColor, size: 26.sp),
              ),
              SizedBox(width: 14.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(title,
                            style: TextStyle(
                                fontSize: 15.5.sp,
                                fontWeight: FontWeight.w700,
                                color: AppColors.ink)),
                        if (count > 0) ...[
                          SizedBox(width: 8.w),
                          MChip('$count added',
                              background: AppColors.successSoft,
                              foreground: AppColors.success),
                        ],
                      ],
                    ),
                    SizedBox(height: 4.h),
                    Text(description,
                        style: TextStyle(
                            fontSize: 12.5.sp,
                            color: AppColors.muted,
                            height: 1.35)),
                  ],
                ),
              ),
              SizedBox(width: 8.w),
              Container(
                width: 30.r,
                height: 30.r,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.line, width: 1.4),
                ),
                child: Icon(Icons.add_rounded,
                    size: 18.sp, color: AppColors.ink),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashedRRectPainter extends CustomPainter {
  _DashedRRectPainter({required this.color, required this.radius});
  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
        Offset.zero & size, Radius.circular(radius));
    final path = Path()..addRRect(rrect);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;

    const dashWidth = 5.0;
    const dashGap = 4.0;
    for (final metric in path.computeMetrics()) {
      double distance = 0;
      while (distance < metric.length) {
        final next = distance + dashWidth;
        canvas.drawPath(
            metric.extractPath(distance, next.clamp(0, metric.length)),
            paint);
        distance = next + dashGap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRRectPainter oldDelegate) =>
      oldDelegate.color != color;
}

// ─────────────────────────── Shared wizard chrome ───────────────────────────

class _WizardScaffold extends StatelessWidget {
  const _WizardScaffold({
    required this.title,
    required this.step,
    required this.totalSteps,
    required this.child,
    required this.onBack,
    this.bottomButton,
    this.onSkip,
  });

  final String title;
  final int step; // 0-indexed
  final int totalSteps;
  final Widget child;
  final VoidCallback onBack;
  final Widget? bottomButton;
  final VoidCallback? onSkip;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: onBack,
        ),
        title: Text(title),
        actions: [
          if (onSkip != null)
            TextButton(
              onPressed: onSkip,
              child: Text('Skip',
                  style: TextStyle(
                      color: AppColors.muted,
                      fontWeight: FontWeight.w700,
                      fontSize: 13.sp)),
            ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(20.w, 8.h, 20.w, 16.h),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: List.generate(totalSteps, (i) {
                  final active = i <= step;
                  return Expanded(
                    child: Container(
                      margin: EdgeInsets.only(
                          right: i == totalSteps - 1 ? 0 : 6.w),
                      height: 5.h,
                      decoration: BoxDecoration(
                        color:
                        active ? AppColors.primary : AppColors.line,
                        borderRadius: BorderRadius.circular(10.r),
                      ),
                    ),
                  );
                }),
              ),
              SizedBox(height: 20.h),
              Expanded(child: SingleChildScrollView(child: child)),
              if (bottomButton != null) ...[
                SizedBox(height: 12.h),
                bottomButton!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _StepLabel extends StatelessWidget {
  const _StepLabel(this.text, {this.sub});
  final String text;
  final String? sub;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: 16.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(text,
              style: TextStyle(
                  fontSize: 19.sp,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink)),
          if (sub != null) ...[
            SizedBox(height: 4.h),
            Text(sub!,
                style: TextStyle(fontSize: 13.sp, color: AppColors.muted)),
          ],
        ],
      ),
    );
  }
}

class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    required this.label,
    required this.selected,
    required this.onTap,
    this.sub,
  });

  final String label;
  final String? sub;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: 10.h),
      child: MCard(
        onTap: onTap,
        color: selected ? AppColors.soft : AppColors.card,
        border: Border.all(
            color: selected ? AppColors.primary : AppColors.line,
            width: selected ? 1.6 : 1),
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          fontSize: 14.5.sp,
                          fontWeight: FontWeight.w700,
                          color:
                          selected ? AppColors.onSoft : AppColors.ink)),
                  if (sub != null)
                    Text(sub!,
                        style: TextStyle(
                            fontSize: 12.sp, color: AppColors.muted)),
                ],
              ),
            ),
            if (selected)
              const Icon(Icons.check_circle_rounded,
                  color: AppColors.primary),
          ],
        ),
      ),
    );
  }
}

Widget _labeledField({
  required String label,
  required Widget child,
}) {
  return Builder(builder: (context) {
    return Padding(
      padding: EdgeInsets.only(bottom: 16.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 13.sp,
                  fontWeight: FontWeight.w700,
                  color: AppColors.inkSoft)),
          SizedBox(height: 6.h),
          child,
        ],
      ),
    );
  });
}

String _fmtTime(TimeOfDay t) {
  final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
  final m = t.minute.toString().padLeft(2, '0');
  final p = t.period == DayPeriod.am ? 'AM' : 'PM';
  return '$h:$m $p';
}

// ───────────────────────────── Medications wizard ────────────────────────────

class _MedicationWizard extends StatefulWidget {
  const _MedicationWizard();

  @override
  State<_MedicationWizard> createState() => _MedicationWizardState();
}

class _MedicationWizardState extends State<_MedicationWizard> {
  int _step = 0;
  static const _totalSteps = 6;

  String _forWhom = 'Myself';
  final _nameCtrl = TextEditingController();
  String _unit = 'Pill';
  String _frequency = 'Once daily';
  List<TimeOfDay> _times = [const TimeOfDay(hour: 8, minute: 0)];
  DateTime _startDate = DateTime.now();
  final _doseCtrl = TextEditingController(text: '1');
  bool _inventoryOn = false;
  final _amountCtrl = TextEditingController(text: '30');
  final _thresholdCtrl = TextEditingController(text: '5');
  final _conditionCtrl = TextEditingController();
  bool _saving = false;

  int get _timesNeeded {
    switch (_frequency) {
      case 'Twice daily':
        return 2;
      case 'Three times daily':
        return 3;
      default:
        return 1; // 'Once daily' and 'On demand'
    }
  }

  void _resizeTimes() {
    const defaults = [
      TimeOfDay(hour: 8, minute: 0),
      TimeOfDay(hour: 20, minute: 0),
      TimeOfDay(hour: 14, minute: 0),
    ];
    while (_times.length < _timesNeeded) {
      _times.add(defaults[_times.length % defaults.length]);
    }
    if (_times.length > _timesNeeded) {
      _times = _times.sublist(0, _timesNeeded);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _doseCtrl.dispose();
    _amountCtrl.dispose();
    _thresholdCtrl.dispose();
    _conditionCtrl.dispose();
    super.dispose();
  }

  void _next() {
    if (_step == 1 && _nameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter the medication name')));
      return;
    }
    if (_step == _totalSteps - 1) {
      _save();
      return;
    }
    setState(() => _step++);
  }

  void _back() {
    if (_step == 0) {
      Navigator.pop(context, false);
    } else {
      setState(() => _step--);
    }
  }

  void _skip() {
    if (_step == _totalSteps - 1) {
      _save();
    } else {
      setState(() => _step++);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final timesLabel = _times.map(_fmtTime).join(', ');
    final reminder = Reminder(
      title: _nameCtrl.text.trim(),
      dose: '${_doseCtrl.text.trim()} $_unit',
      time: timesLabel,
      schedule: _frequency,
      instructions: _conditionCtrl.text.trim(),
      category: 'medication',
      unit: _unit,
      forWhom: _forWhom,
      conditionTag:
      _conditionCtrl.text.trim().isEmpty ? null : _conditionCtrl.text.trim(),
      inventoryEnabled: _inventoryOn,
      inventoryAmount: _inventoryOn ? int.tryParse(_amountCtrl.text) : null,
      inventoryThreshold:
      _inventoryOn ? int.tryParse(_thresholdCtrl.text) : null,
    );
    await context.read<ReminderProvider>().add(reminder);
    if (!mounted) return;
    setState(() => _saving = false);
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16.r)),
        title: const Text('Reminder set'),
        content: Text(
            "We'll remind you to take ${_nameCtrl.text.trim()} at $timesLabel."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    late Widget content;
    switch (_step) {
      case 0:
        content = _stepWho();
        break;
      case 1:
        content = _stepNameUnit();
        break;
      case 2:
        content = _stepFrequency();
        break;
      case 3:
        content = _stepTimeDose();
        break;
      case 4:
        content = _stepInventory();
        break;
      default:
        content = _stepCondition();
    }

    return _WizardScaffold(
      title: 'Add medication',
      step: _step,
      totalSteps: _totalSteps,
      onBack: _back,
      onSkip: (_step == 0 || _step == 4 || _step == 5) && !_saving
          ? _skip
          : null,
      bottomButton: PrimaryButton(
        label: _saving
            ? 'Saving…'
            : (_step == _totalSteps - 1 ? 'Save reminder' : 'Continue'),
        onPressed: _saving ? null : _next,
      ),
      child: content,
    );
  }

  Widget _stepWho() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _StepLabel('Who is this medication for?'),
        _ChoiceTile(
          label: 'Myself',
          sub: 'I manage my own treatment',
          selected: _forWhom == 'Myself',
          onTap: () => setState(() => _forWhom = 'Myself'),
        ),
        _ChoiceTile(
          label: 'Someone else',
          sub: 'I manage treatment for a family member',
          selected: _forWhom == 'Someone else',
          onTap: () => setState(() => _forWhom = 'Someone else'),
        ),
      ],
    );
  }

  Widget _stepNameUnit() {
    const units = ['Pill', 'Tablet', 'Capsule', 'Spray', 'mL', 'Injection'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _StepLabel('What medication are you taking?'),
        _labeledField(
          label: 'Medication name',
          child: TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(hintText: 'e.g. Metformin'),
          ),
        ),
        _labeledField(
          label: 'Unit',
          child: Wrap(
            spacing: 8.w,
            runSpacing: 8.h,
            children: units
                .map((u) => ChoiceChip(
              label: Text(u),
              selected: _unit == u,
              selectedColor: AppColors.soft,
              labelStyle: TextStyle(
                  color: _unit == u
                      ? AppColors.onSoft
                      : AppColors.ink,
                  fontWeight: FontWeight.w600),
              side: BorderSide(
                  color:
                  _unit == u ? AppColors.primary : AppColors.line),
              onSelected: (_) => setState(() => _unit = u),
            ))
                .toList(),
          ),
        ),
      ],
    );
  }

  Widget _stepFrequency() {
    const options = ['Once daily', 'Twice daily', 'Three times daily', 'On demand'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _StepLabel('How often do you take it?'),
        for (final o in options)
          _ChoiceTile(
            label: o,
            selected: _frequency == o,
            onTap: () => setState(() {
              _frequency = o;
              _resizeTimes();
            }),
          ),
      ],
    );
  }

  Widget _stepTimeDose() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _StepLabel('Time, start date & dose'),
        _labeledField(
          label: _times.length > 1 ? 'Reminder times' : 'Reminder time',
          child: Column(
            children: [
              for (var i = 0; i < _times.length; i++)
                Padding(
                  padding: EdgeInsets.only(
                      bottom: i == _times.length - 1 ? 0 : 8.h),
                  child: _PickerRow(
                    icon: Icons.access_time_rounded,
                    text: _times.length > 1
                        ? 'Dose ${i + 1} · ${_fmtTime(_times[i])}'
                        : _fmtTime(_times[i]),
                    onTap: () async {
                      final picked = await showTimePicker(
                          context: context, initialTime: _times[i]);
                      if (picked != null) {
                        setState(() => _times[i] = picked);
                      }
                    },
                  ),
                ),
            ],
          ),
        ),
        _labeledField(
          label: 'Start date',
          child: _PickerRow(
            icon: Icons.calendar_today_rounded,
            text:
            '${_startDate.day}/${_startDate.month}/${_startDate.year}',
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _startDate,
                firstDate: DateTime.now().subtract(const Duration(days: 1)),
                lastDate: DateTime.now().add(const Duration(days: 3650)),
              );
              if (picked != null) setState(() => _startDate = picked);
            },
          ),
        ),
        _labeledField(
          label: 'Dose (per intake)',
          child: TextField(
            controller: _doseCtrl,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(suffixText: _unit),
          ),
        ),
      ],
    );
  }

  Widget _stepInventory() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _StepLabel('Refill reminder',
            sub: 'Get notified before you run out — optional'),
        MCard(
          padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
          child: Row(
            children: [
              Expanded(
                child: Text('Track inventory',
                    style: TextStyle(
                        fontSize: 14.sp, fontWeight: FontWeight.w600)),
              ),
              Switch(
                value: _inventoryOn,
                activeColor: AppColors.primary,
                onChanged: (v) => setState(() => _inventoryOn = v),
              ),
            ],
          ),
        ),
        if (_inventoryOn) ...[
          SizedBox(height: 16.h),
          _labeledField(
            label: 'Current amount',
            child: TextField(
              controller: _amountCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(suffixText: _unit),
            ),
          ),
          _labeledField(
            label: 'Remind me when below',
            child: TextField(
              controller: _thresholdCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(suffixText: _unit),
            ),
          ),
        ],
      ],
    );
  }

  Widget _stepCondition() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _StepLabel('What do you take this for?',
            sub: 'Optional — helps MedAI give you better guidance'),
        _labeledField(
          label: 'Condition or reason',
          child: TextField(
            controller: _conditionCtrl,
            decoration:
            const InputDecoration(hintText: 'e.g. Blood pressure'),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────── Measurements / Activities wizard ───────────────────

class _CategoryPickerWizard extends StatefulWidget {
  const _CategoryPickerWizard({required this.category});
  final String category; // 'measurement' | 'activity'

  @override
  State<_CategoryPickerWizard> createState() => _CategoryPickerWizardState();
}

class _CategoryPickerWizardState extends State<_CategoryPickerWizard> {
  static const _measurementOptions = [
    'Blood pressure', 'Weight', 'Blood sugar', 'Heart rate',
    'Sodium', 'TSH', 'Temperature', 'Oxygen saturation',
  ];
  static const _activityOptions = [
    'Walking', 'Stretching', 'Hiking', 'Gardening',
    'Drinking water', 'Meditation', 'Cycling', 'Yoga',
  ];

  int _step = 0;
  String? _selected;
  final _customCtrl = TextEditingController();

  String _frequency = 'Daily';
  int _everyX = 3;
  final Set<int> _weekdays = {}; // 1=Mon..7=Sun
  TimeOfDay _time = const TimeOfDay(hour: 9, minute: 0);
  String _unit = 'mmHg';
  final _durationCtrl = TextEditingController(text: '5');
  bool _saving = false;

  bool get isMeasurement => widget.category == 'measurement';

  @override
  void dispose() {
    _customCtrl.dispose();
    _durationCtrl.dispose();
    super.dispose();
  }

  String get _name =>
      _selected ?? (_customCtrl.text.trim().isEmpty ? '' : _customCtrl.text.trim());

  void _back() {
    if (_step == 0) {
      Navigator.pop(context, false);
    } else {
      setState(() => _step--);
    }
  }

  void _next() {
    if (_step == 0 && _name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Please choose or name a ${isMeasurement ? 'measurement' : 'activity'}')));
      return;
    }
    if (_step == 2) {
      _save();
      return;
    }
    setState(() => _step++);
  }

  String get _scheduleLabel {
    switch (_frequency) {
      case 'Every X days':
        return 'Every $_everyX days';
      case 'Specific days':
        if (_weekdays.isEmpty) return 'Specific days';
        const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
        final sorted = _weekdays.toList()..sort();
        return sorted.map((d) => names[d - 1]).join(' · ');
      case 'On demand':
        return 'On demand';
      default:
        return 'Daily';
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final reminder = Reminder(
      title: _name,
      dose: isMeasurement ? '' : '${_durationCtrl.text.trim()} min',
      time: _frequency == 'On demand' ? 'One-time entry' : _fmtTime(_time),
      schedule: _scheduleLabel,
      category: widget.category,
      unit: isMeasurement ? _unit : null,
      durationLabel: isMeasurement ? null : '${_durationCtrl.text.trim()} min',
    );
    await context.read<ReminderProvider>().add(reminder);
    if (!mounted) return;
    setState(() => _saving = false);
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    late Widget content;
    switch (_step) {
      case 0:
        content = _stepPick();
        break;
      case 1:
        content = _stepFrequency();
        break;
      default:
        content = _stepDetail();
    }

    return _WizardScaffold(
      title: isMeasurement ? 'Add measurement' : 'Add activity',
      step: _step,
      totalSteps: 3,
      onBack: _back,
      bottomButton: PrimaryButton(
        label: _saving
            ? 'Saving…'
            : (_step == 2 ? 'Save reminder' : 'Continue'),
        onPressed: _saving ? null : _next,
      ),
      child: content,
    );
  }

  Widget _stepPick() {
    final options = isMeasurement ? _measurementOptions : _activityOptions;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StepLabel(isMeasurement
            ? 'What would you like to measure?'
            : 'What activity would you like to track?'),
        Wrap(
          spacing: 8.w,
          runSpacing: 8.h,
          children: options
              .map((o) => ChoiceChip(
            label: Text(o),
            selected: _selected == o,
            selectedColor: AppColors.soft,
            labelStyle: TextStyle(
                color: _selected == o
                    ? AppColors.onSoft
                    : AppColors.ink,
                fontWeight: FontWeight.w600),
            side: BorderSide(
                color: _selected == o
                    ? AppColors.primary
                    : AppColors.line),
            onSelected: (_) => setState(() {
              _selected = o;
              _customCtrl.clear();
            }),
          ))
              .toList(),
        ),
        SizedBox(height: 20.h),
        _labeledField(
          label: 'Or create with a custom name',
          child: TextField(
            controller: _customCtrl,
            onChanged: (v) => setState(() => _selected = null),
            decoration: const InputDecoration(hintText: 'e.g. Sleep hours'),
          ),
        ),
      ],
    );
  }

  Widget _stepFrequency() {
    const options = ['Daily', 'Every X days', 'Specific days', 'On demand'];
    const weekNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _StepLabel('How often?'),
        for (final o in options)
          _ChoiceTile(
            label: o,
            selected: _frequency == o,
            onTap: () => setState(() => _frequency = o),
          ),
        if (_frequency == 'Every X days') ...[
          SizedBox(height: 8.h),
          _labeledField(
            label: 'Repeat every',
            child: Row(
              children: [
                IconButton(
                  onPressed: () => setState(
                          () => _everyX = (_everyX - 1).clamp(1, 30)),
                  icon: const Icon(Icons.remove_circle_outline_rounded),
                ),
                Text('$_everyX days',
                    style: TextStyle(
                        fontSize: 15.sp, fontWeight: FontWeight.w700)),
                IconButton(
                  onPressed: () => setState(
                          () => _everyX = (_everyX + 1).clamp(1, 30)),
                  icon: const Icon(Icons.add_circle_outline_rounded),
                ),
              ],
            ),
          ),
        ],
        if (_frequency == 'Specific days') ...[
          SizedBox(height: 8.h),
          Wrap(
            spacing: 8.w,
            runSpacing: 8.h,
            children: List.generate(7, (i) {
              final d = i + 1;
              final sel = _weekdays.contains(d);
              return ChoiceChip(
                label: Text(weekNames[i]),
                selected: sel,
                selectedColor: AppColors.soft,
                labelStyle: TextStyle(
                    color: sel ? AppColors.onSoft : AppColors.ink,
                    fontWeight: FontWeight.w600),
                side: BorderSide(
                    color: sel ? AppColors.primary : AppColors.line),
                onSelected: (_) => setState(
                        () => sel ? _weekdays.remove(d) : _weekdays.add(d)),
              );
            }),
          ),
        ],
        if (_frequency == 'On demand') ...[
          SizedBox(height: 8.h),
          Text('One-time entry — no scheduled intakes will be created.',
              style: TextStyle(fontSize: 12.5.sp, color: AppColors.muted)),
        ],
      ],
    );
  }

  Widget _stepDetail() {
    const measurementUnits = ['mmHg', 'kg', 'mg/dL', 'bpm', '°C', '%'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _StepLabel('A few final details'),
        if (_frequency != 'On demand')
          _labeledField(
            label: 'Reminder time',
            child: _PickerRow(
              icon: Icons.access_time_rounded,
              text: _fmtTime(_time),
              onTap: () async {
                final picked = await showTimePicker(
                    context: context, initialTime: _time);
                if (picked != null) setState(() => _time = picked);
              },
            ),
          ),
        if (isMeasurement)
          _labeledField(
            label: 'Unit',
            child: Wrap(
              spacing: 8.w,
              runSpacing: 8.h,
              children: measurementUnits
                  .map((u) => ChoiceChip(
                label: Text(u),
                selected: _unit == u,
                selectedColor: AppColors.soft,
                labelStyle: TextStyle(
                    color: _unit == u
                        ? AppColors.onSoft
                        : AppColors.ink,
                    fontWeight: FontWeight.w600),
                side: BorderSide(
                    color: _unit == u
                        ? AppColors.primary
                        : AppColors.line),
                onSelected: (_) => setState(() => _unit = u),
              ))
                  .toList(),
            ),
          )
        else
          _labeledField(
            label: 'Duration',
            child: TextField(
              controller: _durationCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(suffixText: 'minutes'),
            ),
          ),
      ],
    );
  }
}

class _PickerRow extends StatelessWidget {
  const _PickerRow(
      {required this.icon, required this.text, required this.onTap});
  final IconData icon;
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MCard(
      onTap: onTap,
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
      child: Row(
        children: [
          Icon(icon, size: 18.sp, color: AppColors.primary),
          SizedBox(width: 10.w),
          Text(text,
              style:
              TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}