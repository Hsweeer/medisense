import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/services/prescription_history_preferences.dart';
import '../../core/services/prescription_log_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/shared_widgets.dart';
import '../../data/models/prescription_models.dart';

/// Prescription history with three professional sections:
/// **New** (last 30 days), **Old** (older), and **All**.
class PrescriptionHistoryScreen extends StatefulWidget {
  const PrescriptionHistoryScreen({super.key});

  @override
  State<PrescriptionHistoryScreen> createState() =>
      _PrescriptionHistoryScreenState();
}

enum _HistoryTab { neu, old, all }

class _PrescriptionHistoryScreenState extends State<PrescriptionHistoryScreen> {
  bool _enabled = true;
  bool _loading = true;
  _HistoryTab _tab = _HistoryTab.neu;

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

  List<PrescriptionHistoryEntry> _filter(
      List<PrescriptionHistoryEntry> all,
      ) {
    switch (_tab) {
      case _HistoryTab.neu:
        return all.where((e) => e.isNew).toList();
      case _HistoryTab.old:
        return all.where((e) => !e.isNew).toList();
      case _HistoryTab.all:
        return all;
    }
  }

  String _emptyMessage() {
    switch (_tab) {
      case _HistoryTab.neu:
        return 'No recent prescriptions yet.\nScan one to see it under New.';
      case _HistoryTab.old:
        return 'No older prescriptions yet.\nScans older than 30 days appear here.';
      case _HistoryTab.all:
        return 'No prescription history yet.\nScan a prescription to get started.';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        backgroundColor: AppColors.paper,
        surfaceTintColor: AppColors.paper,
        title: const Text('Prescription history'),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(20.w, 12.h, 20.w, 28.h),
        children: [
          Card(
            elevation: 0,
            color: AppColors.card,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14.r),
              side: BorderSide(color: AppColors.line),
            ),
            child: SwitchListTile.adaptive(
              value: _loading ? true : _enabled,
              onChanged: _loading ? null : _toggle,
              activeThumbColor: AppColors.primary,
              title: Text(
                'Save prescription history',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14.sp,
                ),
              ),
              subtitle: Text(
                'Keep scanned prescriptions so you can revisit New, Old, or All anytime.',
                style: TextStyle(fontSize: 12.sp, color: AppColors.muted),
              ),
            ),
          ),
          SizedBox(height: 16.h),
          if (!_enabled && !_loading)
            Container(
              padding: EdgeInsets.all(14.r),
              decoration: BoxDecoration(
                color: AppColors.warningSoft,
                borderRadius: BorderRadius.circular(12.r),
              ),
              child: Text(
                'History saving is off. New scans will not be added.',
                style: TextStyle(fontSize: 13.sp, color: AppColors.warning),
              ),
            ),
          if (_enabled && !_loading) ...[
            _SegmentedTabs(
              tab: _tab,
              onChanged: (t) => setState(() => _tab = t),
            ),
            SizedBox(height: 6.h),
            Text(
              _tab == _HistoryTab.neu
                  ? 'Last 30 days'
                  : _tab == _HistoryTab.old
                  ? 'Older than 30 days'
                  : 'Everything you\'ve saved',
              style: TextStyle(fontSize: 11.5.sp, color: AppColors.muted),
            ),
            SizedBox(height: 14.h),
            StreamBuilder<List<PrescriptionHistoryEntry>>(
              stream: PrescriptionLogService.instance.allEntries(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Text(
                    'Could not load prescription history.',
                    style: TextStyle(color: AppColors.danger, fontSize: 13.sp),
                  );
                }
                if (!snapshot.hasData) {
                  return Padding(
                    padding: EdgeInsets.symmetric(vertical: 40.h),
                    child: const Center(child: CircularProgressIndicator()),
                  );
                }
                final filtered = _filter(snapshot.data!);
                if (filtered.isEmpty) {
                  return _EmptyState(message: _emptyMessage());
                }
                return Column(
                  children: filtered.map((e) => _EntryCard(
                    entry: e,
                    onOpen: () => _showSummary(e),
                    onDelete: () => _confirmDelete(e),
                  )).toList(),
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  void _showSummary(PrescriptionHistoryEntry entry) {
    final path = entry.photoUrl;
    final dialogWidth = MediaQuery.of(context).size.width * 0.85;

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18.r)),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Prescription summary',
              style: GoogleFonts.sora(
                fontSize: 16.sp,
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
              ),
            ),
            SizedBox(height: 4.h),
            Text(
              '${_formatDate(entry.scannedAt)} · '
                  '${entry.medicineCount} medicine'
                  '${entry.medicineCount == 1 ? '' : 's'} · '
                  '${entry.isNew ? 'New' : 'Old'}',
              style: TextStyle(fontSize: 12.sp, color: AppColors.muted),
            ),
          ],
        ),
        content: SizedBox(
          width: dialogWidth,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (path != null && path.isNotEmpty)
                  Padding(
                    padding: EdgeInsets.only(bottom: 12.h),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12.r),
                      child: SizedBox(
                        width: dialogWidth,
                        height: 160.h,
                        child: Image.file(
                          File(path),
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                          const SizedBox.shrink(),
                        ),
                      ),
                    ),
                  ),
                SelectableText(
                  entry.summary,
                  style: TextStyle(
                    fontSize: 13.sp,
                    height: 1.55,
                    color: AppColors.inkSoft,
                  ),
                ),
              ],
            ),
          ),
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

// ── Tabs ───────────────────────────────────────────────────────────────

class _SegmentedTabs extends StatelessWidget {
  const _SegmentedTabs({required this.tab, required this.onChanged});

  final _HistoryTab tab;
  final ValueChanged<_HistoryTab> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(4.r),
      decoration: BoxDecoration(
        color: AppColors.soft,
        borderRadius: BorderRadius.circular(12.r),
      ),
      child: Row(
        children: [
          _TabChip(
            label: 'New',
            selected: tab == _HistoryTab.neu,
            onTap: () => onChanged(_HistoryTab.neu),
          ),
          _TabChip(
            label: 'Old',
            selected: tab == _HistoryTab.old,
            onTap: () => onChanged(_HistoryTab.old),
          ),
          _TabChip(
            label: 'All',
            selected: tab == _HistoryTab.all,
            onTap: () => onChanged(_HistoryTab.all),
          ),
        ],
      ),
    );
  }
}

class _TabChip extends StatelessWidget {
  const _TabChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: selected ? AppColors.primary : Colors.transparent,
        borderRadius: BorderRadius.circular(10.r),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10.r),
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 10.h),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5.sp,
                fontWeight: FontWeight.w700,
                color: selected ? Colors.white : AppColors.inkSoft,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Entry card ─────────────────────────────────────────────────────────

class _EntryCard extends StatelessWidget {
  const _EntryCard({
    required this.entry,
    required this.onOpen,
    required this.onDelete,
  });

  final PrescriptionHistoryEntry entry;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: 10.h),
      child: Material(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14.r),
        child: InkWell(
          onTap: onOpen,
          borderRadius: BorderRadius.circular(14.r),
          child: Container(
            padding: EdgeInsets.all(12.r),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14.r),
              border: Border.all(color: AppColors.line),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Thumbnail(path: entry.photoUrl),
                SizedBox(width: 12.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${entry.medicineCount} medicine'
                                  '${entry.medicineCount == 1 ? '' : 's'}',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 14.sp,
                                color: AppColors.ink,
                              ),
                            ),
                          ),
                          _StatusChip(isNew: entry.isNew),
                        ],
                      ),
                      SizedBox(height: 3.h),
                      Text(
                        _formatDate(entry.scannedAt),
                        style: TextStyle(
                          fontSize: 11.5.sp,
                          color: AppColors.muted,
                        ),
                      ),
                      SizedBox(height: 6.h),
                      Text(
                        entry.preview,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.sp,
                          height: 1.35,
                          color: AppColors.inkSoft,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Delete',
                  icon: Icon(
                    Icons.delete_outline_rounded,
                    color: AppColors.danger,
                    size: 20.sp,
                  ),
                  onPressed: onDelete,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.isNew});
  final bool isNew;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
      decoration: BoxDecoration(
        color: isNew ? AppColors.soft : AppColors.line.withValues(alpha: .6),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        isNew ? 'New' : 'Old',
        style: TextStyle(
          fontSize: 10.5.sp,
          fontWeight: FontWeight.w700,
          color: isNew ? AppColors.primaryDark : AppColors.muted,
        ),
      ),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.path});
  final String? path;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      width: 56.r,
      height: 56.r,
      decoration: BoxDecoration(
        color: AppColors.soft,
        borderRadius: BorderRadius.circular(12.r),
      ),
      child: Icon(
        Icons.receipt_long_rounded,
        size: 24.sp,
        color: AppColors.muted,
      ),
    );

    if (path == null || path!.isEmpty) return placeholder;

    return ClipRRect(
      borderRadius: BorderRadius.circular(12.r),
      child: Image.file(
        File(path!),
        width: 56.r,
        height: 56.r,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => placeholder,
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 36.h),
      child: Column(
        children: [
          Container(
            width: 64.r,
            height: 64.r,
            decoration: BoxDecoration(
              color: AppColors.soft,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.folder_open_rounded,
              size: 28.sp,
              color: AppColors.primary,
            ),
          ),
          SizedBox(height: 14.h),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13.5.sp,
              height: 1.45,
              color: AppColors.muted,
            ),
          ),
        ],
      ),
    );
  }
}

const _monthNames = [
  '',
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String _formatDate(DateTime date) {
  final local = date.toLocal();
  return '${_monthNames[local.month]} ${local.day}, ${local.year}';
}