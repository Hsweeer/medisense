import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_loading.dart';
import '../../core/widgets/shared_widgets.dart';
import '../../data/models/notification_model.dart';
import '../../providers/notification_provider.dart';

/// Full notification history — local-only, newest first.
class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<NotificationProvider>();
    debugPrint(
      '[NotificationsScreen] build() — ${prov.notifications.length} notifications, isLoading=${prov.isLoading}',
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          if (prov.notifications.isNotEmpty)
            TextButton(
              onPressed: () => _confirmClearAll(context),
              child: const Text(
                'Clear all',
                style: TextStyle(
                  color: AppColors.danger,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: () => context.read<NotificationProvider>().refresh(),
        child: prov.isLoading
            ? const _LoadingState()
            : prov.notifications.isEmpty
            ? const _EmptyState()
            : ListView.builder(
                padding: EdgeInsets.fromLTRB(20.w, 8.h, 20.w, 24.h),
                itemCount: prov.notifications.length,
                itemBuilder: (context, i) {
                  final item = prov.notifications[i];
                  return Padding(
                    padding: EdgeInsets.only(bottom: 10.h),
                    child: _NotificationCard(item: item),
                  );
                },
              ),
      ),
    );
  }

  void _confirmClearAll(BuildContext context) async {
    final confirmed = await AppDialog.confirm(
      context: context,
      title: 'Clear all notifications?',
      message:
          'This removes your entire local notification history. This action cannot be undone.',
      confirmText: 'Clear all',
      destructive: true,
      icon: Icons.delete_outline_rounded,
    );

    if (!confirmed || !context.mounted) return;

    context.read<NotificationProvider>().clearAll();
    showToast(context, 'Notification history cleared');
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({required this.item});

  final NotificationItem item;

  @override
  Widget build(BuildContext context) {
    final prov = context.read<NotificationProvider>();

    return Dismissible(
      key: ValueKey(item.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: EdgeInsets.symmetric(horizontal: 22.w),
        margin: const EdgeInsets.only(bottom: 0),
        decoration: BoxDecoration(
          color: AppColors.dangerSoft,
          borderRadius: BorderRadius.circular(18.r),
        ),
        child: Icon(
          Icons.delete_outline_rounded,
          color: AppColors.danger,
          size: 24.sp,
        ),
      ),
      onDismissed: (_) {
        prov.delete(item);
        showToast(context, 'Notification deleted');
      },
      child: MCard(
        padding: EdgeInsets.all(14.r),
        color: item.isRead ? AppColors.card : AppColors.soft,
        border: Border.all(
          color: item.isRead
              ? AppColors.line
              : AppColors.primary.withValues(alpha: .3),
        ),
        onTap: () => prov.markAsRead(item),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42.r,
              height: 42.r,
              decoration: BoxDecoration(
                color: item.isRead ? AppColors.paper : Colors.white,
                borderRadius: BorderRadius.circular(13.r),
              ),
              child: Icon(
                Icons.medication_rounded,
                color: AppColors.primary,
                size: 22.sp,
              ),
            ),
            SizedBox(width: 12.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.title,
                          style: TextStyle(
                            fontSize: 14.5.sp,
                            fontWeight: item.isRead
                                ? FontWeight.w600
                                : FontWeight.w700,
                            color: AppColors.ink,
                          ),
                        ),
                      ),
                      if (!item.isRead)
                        Container(
                          width: 8.r,
                          height: 8.r,
                          margin: EdgeInsets.only(left: 8.w, top: 3.h),
                          decoration: const BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                  SizedBox(height: 3.h),
                  Text(
                    item.message,
                    style: TextStyle(
                      fontSize: 12.5.sp,
                      color: AppColors.muted,
                      height: 1.35,
                    ),
                  ),
                  SizedBox(height: 8.h),
                  Row(
                    children: [
                      MChip(
                        item.date,
                        icon: Icons.event_rounded,
                        background: AppColors.paper,
                        foreground: AppColors.inkSoft,
                      ),
                      SizedBox(width: 6.w),
                      MChip(
                        item.time,
                        icon: Icons.schedule_rounded,
                        background: AppColors.paper,
                        foreground: AppColors.inkSoft,
                      ),
                      const Spacer(),
                      if (item.isRead)
                        Icon(
                          Icons.done_all_rounded,
                          size: 16.sp,
                          color: AppColors.muted,
                        )
                      else
                        Icon(
                          Icons.fiber_manual_record_rounded,
                          size: 8.sp,
                          color: AppColors.primary,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Padding(
              padding: EdgeInsets.all(32.r),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 96.r,
                    height: 96.r,
                    decoration: BoxDecoration(
                      color: AppColors.soft,
                      borderRadius: BorderRadius.circular(28.r),
                    ),
                    child: Icon(
                      Icons.notifications_none_rounded,
                      size: 46.sp,
                      color: AppColors.primary,
                    ),
                  ),
                  SizedBox(height: 18.h),
                  Text(
                    'No notifications yet.',
                    style: GoogleFonts.sora(
                      fontSize: 17.sp,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                  SizedBox(height: 6.h),
                  Text(
                    'Reminders and updates will show up here as they arrive.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13.sp, color: AppColors.muted),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: const Center(
            child: AppSectionLoader(label: 'Loading notifications…'),
          ),
        ),
      ),
    );
  }
}