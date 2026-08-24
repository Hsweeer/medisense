import 'package:flutter/material.dart';

import '../../../core/services/caregiver_service.dart';
import '../../../data/models/caregiver_models.dart';
import '../../../data/models/models.dart';

class CreateCaregiverReminderScreen extends StatefulWidget {
  const CreateCaregiverReminderScreen({super.key});

  @override
  State<CreateCaregiverReminderScreen> createState() =>
      _CreateCaregiverReminderScreenState();
}

class _CreateCaregiverReminderScreenState
    extends State<CreateCaregiverReminderScreen> {
  final Set<String> _selectedRecipientUids = {};
  bool _directAssign = true;

  final _titleController = TextEditingController();
  final _doseController = TextEditingController();
  final _timeController = TextEditingController();
  bool _saving = false;

  Future<void> _save() async {
    if (_selectedRecipientUids.isEmpty ||
        _titleController.text.trim().isEmpty) {
      return;
    }

    setState(() => _saving = true);

    final reminder = Reminder(
      title: _titleController.text.trim(),
      dose: _directAssign ? _doseController.text.trim() : '',
      time: _timeController.text.trim().isEmpty
          ? '9:00 AM'
          : _timeController.text.trim(),
      schedule: 'Daily',
      addedBy: 'caregiver',
    );

    try {
      await CaregiverService.instance.createReminderForRecipients(
        reminder: reminder,
        recipientUids: _selectedRecipientUids.toList(),
      );
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not create reminder: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New reminder for someone')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Recipients',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          StreamBuilder<List<CaregiverLink>>(
            stream: CaregiverService.instance.myAcceptedRecipients(),
            builder: (context, snapshot) {
              final links = snapshot.data ?? [];
              if (links.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'No accepted recipients yet — send a request first.',
                  ),
                );
              }
              return Wrap(
                spacing: 8,
                children: links.map((l) {
                  final selected = _selectedRecipientUids.contains(
                    l.recipientUid,
                  );
                  return FilterChip(
                    label: Text(l.recipientName),
                    selected: selected,
                    onSelected: (v) => setState(() {
                      v
                          ? _selectedRecipientUids.add(l.recipientUid)
                          : _selectedRecipientUids.remove(l.recipientUid);
                    }),
                  );
                }).toList(),
              );
            },
          ),
          const SizedBox(height: 20),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: true, label: Text('Direct Assign')),
              ButtonSegment(value: false, label: Text('Simple note')),
            ],
            selected: {_directAssign},
            onSelectionChanged: (s) => setState(() => _directAssign = s.first),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _titleController,
            decoration: const InputDecoration(labelText: 'Title'),
          ),
          if (_directAssign) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _doseController,
              decoration: const InputDecoration(
                labelText: 'Dose (e.g. 1 tablet)',
              ),
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _timeController,
            decoration: const InputDecoration(labelText: 'Time (e.g. 8:00 PM)'),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Create reminder'),
          ),
        ],
      ),
    );
  }
}
