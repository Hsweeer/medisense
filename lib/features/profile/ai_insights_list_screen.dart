import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/shared_widgets.dart';
import '../../data/models/models.dart';
import '../../providers/profile_provider.dart';

class AiInsightsListScreen extends StatelessWidget {
  const AiInsightsListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<ProfileProvider>();
    final insights = prov.aiInsights;

    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        title: const Text('AI Insights'),
        backgroundColor: AppColors.paper,
        surfaceTintColor: AppColors.paper,
      ),
      body: insights.isEmpty
          ? Center(
              child: Padding(
                padding: EdgeInsets.all(32.r),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.auto_awesome_rounded,
                        color: AppColors.ai.withValues(alpha: .2), size: 64.sp),
                    SizedBox(height: 16.h),
                    Text(
                      'No insights yet',
                      style: TextStyle(
                        fontSize: 18.sp,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                    SizedBox(height: 8.h),
                    Text(
                      'As you chat with MedAI, useful context like symptoms or concerns will show up here.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14.sp,
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
            )
          : ListView.separated(
              padding: EdgeInsets.fromLTRB(20.w, 8.h, 20.w, 32.h),
              itemCount: insights.length,
              separatorBuilder: (_, __) => SizedBox(height: 12.h),
              itemBuilder: (context, i) {
                final insight = insights[i];
                return _FullInsightCard(
                  insight: insight,
                  onDismiss: () => prov.removeInsight(insight),
                );
              },
            ),
    );
  }
}

class _FullInsightCard extends StatelessWidget {
  const _FullInsightCard({required this.insight, required this.onDismiss});

  final AiInsight insight;
  final VoidCallback onDismiss;

  ({IconData icon, Color color, String label}) get _style {
    switch (insight.type) {
      case AiInsightType.symptom:
        return (icon: Icons.sick_outlined, color: AppColors.warning, label: 'Symptom');
      case AiInsightType.concern:
        return (icon: Icons.priority_high_rounded, color: AppColors.danger, label: 'Concern');
      case AiInsightType.preference:
        return (icon: Icons.tune_rounded, color: AppColors.primary, label: 'Preference');
      case AiInsightType.note:
        return (icon: Icons.notes_rounded, color: AppColors.muted, label: 'Note');
    }
  }

  String get _relativeTime {
    final diff = DateTime.now().difference(insight.createdAt);
    if (diff.inDays > 0) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours}h ago';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
    return 'Just now';
  }

  @override
  Widget build(BuildContext context) {
    final s = _style;
    return MCard(
      padding: EdgeInsets.all(16.r),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32.r,
                height: 32.r,
                decoration: BoxDecoration(
                  color: s.color.withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(8.r),
                ),
                child: Icon(s.icon, color: s.color, size: 16.sp),
              ),
              SizedBox(width: 10.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.label,
                      style: TextStyle(
                        fontSize: 11.sp,
                        fontWeight: FontWeight.w800,
                        color: s.color,
                        letterSpacing: .5,
                      ),
                    ),
                    Text(
                      _relativeTime,
                      style: TextStyle(fontSize: 11.sp, color: AppColors.muted),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onDismiss,
                icon: Icon(Icons.delete_outline_rounded, 
                    size: 20.sp, color: AppColors.muted),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          SizedBox(height: 12.h),
          Text(
            insight.text,
            style: TextStyle(
              fontSize: 14.sp,
              fontWeight: FontWeight.w600,
              color: AppColors.ink,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}
