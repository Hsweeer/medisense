import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../core/services/prescription_history_preferences.dart';
import '../../core/services/prescription_log_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/shared_widgets.dart';
import '../../data/models/prescription_models.dart';

class PrescriptionHistoryScreen extends StatefulWidget {
  const PrescriptionHistoryScreen({super.key});

  @override
  State<PrescriptionHistoryScreen> createState() =>
      _PrescriptionHistoryScreenState();
}

class _PrescriptionHistoryScreenState
    extends State<PrescriptionHistoryScreen> {
  bool _enabled = true;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadPreference();
  }

  Future<void> _loadPreference() async {
    final enabled = await PrescriptionHistoryPreferences.instance.isEnabled();
    if (mounted) {
      setState(() {
        _enabled = enabled;
        _loading = false;
      });
    }
  }

  Future<void> _toggle(bool enabled) async {
    setState(() => _enabled = enabled);
    await PrescriptionHistoryPreferences.instance.setEnabled(enabled);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Prescription history')),
      body: ListView(
        padding: EdgeInsets.all(20.w),
        children: [
          Card(
            child: SwitchListTile.adaptive(
              value: _loading ? true : _enabled,
              onChanged: _loading ? null : _toggle,
              activeThumbColor: AppColors.primary,
              title: const Text('Save prescription history'),
              subtitle: const Text(
                'Keep a summary of every scanned prescription in your account.',
              ),
            ),
          ),
          SizedBox(height: 20.h),
          if (!_enabled && !_loading)
            const Text('History saving is off. New scans will not be added.'),
          if (_enabled && !_loading)
            StreamBuilder<List<PrescriptionHistoryEntry>>(
              stream: PrescriptionLogService.instance.allEntries(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Text('Could not load prescription history.');
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final entries = snapshot.data!;
                if (entries.isEmpty) {
                  return const Text('No prescription history yet.');
                }
                return Column(children: entries.map(_entryTile).toList());
              },
            ),
        ],
      ),
    );
  }

  Widget _entryTile(PrescriptionHistoryEntry entry) {
    return Card(
      margin: EdgeInsets.only(bottom: 10.h),
      child: ListTile(
        title: Text(
          '${entry.medicineCount} medicine${entry.medicineCount == 1 ? '' : 's'}',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(entry.scannedAt.toLocal().toString()),
        trailing: IconButton(
          tooltip: 'Delete prescription entry',
          icon: const Icon(Icons.delete_outline_rounded),
          color: AppColors.danger,
          onPressed: () => _confirmDelete(entry),
        ),
        onTap: () => _showSummary(entry),
      ),
    );
  }

  void _showSummary(PrescriptionHistoryEntry entry) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Prescription summary'),
        content: SingleChildScrollView(
          child: SelectableText(entry.summary,
              style: TextStyle(fontSize: 13.sp, height: 1.5)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(PrescriptionHistoryEntry entry) async {
    final shouldDelete = await AppDialog.confirm(
      context: context,
      title: 'Delete prescription entry?',
      message: 'Remove this scanned prescription from your history?',
      confirmText: 'Delete',
      cancelText: 'Cancel',
      destructive: true,
      icon: Icons.delete_outline_rounded,
    );
    if (shouldDelete != true || entry.id == null || !mounted) return;
    try {
      await PrescriptionLogService.instance.delete(entry.id!);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not delete this entry.')),
        );
      }
    }
  }
}