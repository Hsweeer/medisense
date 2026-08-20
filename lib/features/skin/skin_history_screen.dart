import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/shared_widgets.dart';
import '../../services/skin_scan_firestore_service.dart';

/// Shows past skin scans, most recent first, with a simple comparison
/// against the very first scan on record so the person can see whether
/// things are trending better or worse over time.
class SkinHistoryScreen extends StatefulWidget {
  const SkinHistoryScreen({super.key});

  @override
  State<SkinHistoryScreen> createState() => _SkinHistoryScreenState();
}

class _SkinHistoryScreenState extends State<SkinHistoryScreen> {
  List<SkinScanRecord> _records = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final records = await SkinScanFirestoreService.instance.fetchScans();
    if (!mounted) return;
    setState(() {
      _records = records;
      _loading = false;
    });
  }

  String _relativeTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        backgroundColor: AppColors.paper,
        surfaceTintColor: AppColors.paper,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: AppColors.ink,
        titleSpacing: 0,
        title: Text('Skin scan history',
            style: TextStyle(
                fontSize: 16.5.sp,
                fontWeight: FontWeight.w800,
                color: AppColors.ink)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _records.isEmpty
          ? _EmptyState()
          : ListView(
        padding: EdgeInsets.fromLTRB(20.w, 8.h, 20.w, 24.h),
        children: [
          if (_records.length > 1) _ProgressSummary(records: _records),
          SizedBox(height: 14.h),
          for (final r in _records)
            Padding(
              padding: EdgeInsets.only(bottom: 12.h),
              child: _ScanRow(
                record: r,
                relativeTime: _relativeTime(r.date),
              ),
            ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(30.r),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.face_retouching_natural_rounded,
                size: 42.sp, color: AppColors.muted),
            SizedBox(height: 12.h),
            Text('No skin scans yet',
                style: TextStyle(
                    fontSize: 15.sp, fontWeight: FontWeight.w700)),
            SizedBox(height: 6.h),
            Text(
              'Scan your skin from MedAI chat to start tracking changes over time.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5.sp, color: AppColors.muted),
            ),
          ],
        ),
      ),
    );
  }
}

/// Compares the most recent scan against the very first one on record for
/// each metric — a simple, honest "better / about the same / worse" signal
/// rather than a chart that implies more precision than a handful of
/// cosmetic scans actually supports.
class _ProgressSummary extends StatelessWidget {
  const _ProgressSummary({required this.records});
  final List<SkinScanRecord> records;

  @override
  Widget build(BuildContext context) {
    final latest = records.first; // most recent (list is sorted desc)
    final first = records.last; // oldest on record

    final rows = <Widget>[];
    for (final label in latest.metrics.keys) {
      final latestScore = latest.metrics[label];
      final firstScore = first.metrics[label];
      if (latestScore == null || firstScore == null) continue;
      final delta = latestScore - firstScore;
      // For these cosmetic metrics, lower is generally "better" (less
      // redness, oiliness, blemishes, etc.), so a negative delta reads
      // as improvement.
      final improved = delta < -0.03;
      final worsened = delta > 0.03;
      rows.add(_ProgressRow(label: label, improved: improved, worsened: worsened));
    }
    if (rows.isEmpty) return const SizedBox.shrink();

    return MCard(
      border: Border.all(color: AppColors.ai.withValues(alpha: .45), width: 1.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Since your first scan',
              style: TextStyle(fontSize: 13.5.sp, fontWeight: FontWeight.w700)),
          SizedBox(height: 10.h),
          ...rows,
        ],
      ),
    );
  }
}

class _ProgressRow extends StatelessWidget {
  const _ProgressRow({required this.label, required this.improved, required this.worsened});
  final String label;
  final bool improved;
  final bool worsened;

  @override
  Widget build(BuildContext context) {
    final IconData icon = improved
        ? Icons.trending_down_rounded
        : worsened
        ? Icons.trending_up_rounded
        : Icons.trending_flat_rounded;
    final Color color = improved
        ? AppColors.success
        : worsened
        ? AppColors.warning
        : AppColors.muted;
    final String label2 = improved
        ? 'Improved'
        : worsened
        ? 'Worsened'
        : 'About the same';

    return Padding(
      padding: EdgeInsets.only(bottom: 6.h),
      child: Row(
        children: [
          Icon(icon, size: 15.sp, color: color),
          SizedBox(width: 6.w),
          Expanded(
            child: Text(label, style: TextStyle(fontSize: 12.5.sp)),
          ),
          Text(label2,
              style: TextStyle(
                  fontSize: 12.sp, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }
}

class _ScanRow extends StatelessWidget {
  const _ScanRow({required this.record, required this.relativeTime});
  final SkinScanRecord record;
  final String relativeTime;

  @override
  Widget build(BuildContext context) {
    final topMetric = record.metrics.entries.isEmpty
        ? null
        : (record.metrics.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value)))
        .first;

    return MCard(
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10.r),
            child: record.imagePath != null && File(record.imagePath!).existsSync()
                ? Image.file(File(record.imagePath!),
                width: 48.r, height: 48.r, fit: BoxFit.cover)
                : Container(
              width: 48.r,
              height: 48.r,
              color: AppColors.soft,
              child: Icon(Icons.face_rounded, color: AppColors.muted),
            ),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(relativeTime,
                    style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700)),
                if (topMetric != null)
                  Text(
                    '${topMetric.key}: ${(topMetric.value * 100).round()}% · '
                        '${record.metrics.length} metrics',
                    style: TextStyle(fontSize: 11.5.sp, color: AppColors.muted),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}