import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
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
        '[NotificationsScreen] build() — ${prov.notifications.length} notifications, isLoading=${prov.isLoading}');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          if (prov.notifications.isNotEmpty)
            TextButton(
              onPressed: () => _confirmClearAll(context),
              child: const Text('Clear all',
                  style: TextStyle(
                      color: AppColors.danger, fontWeight: FontWeight.w700)),
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
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          itemCount: prov.notifications.length,
          itemBuilder: (context, i) {
            final item = prov.notifications[i];
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _NotificationCard(item: item),
            );
          },
        ),
      ),
    );
  }

  void _confirmClearAll(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape:
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Clear all notifications?'),
        content: const Text(
            'This removes your entire local notification history. This can\'t be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel',
                style: TextStyle(color: AppColors.muted)),
          ),
          TextButton(
            onPressed: () {
              context.read<NotificationProvider>().clearAll();
              Navigator.of(ctx).pop();
              showToast(context, 'Notification history cleared');
            },
            child: const Text('Clear all',
                style: TextStyle(
                    color: AppColors.danger, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
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
        padding: const EdgeInsets.symmetric(horizontal: 22),
        margin: const EdgeInsets.only(bottom: 0),
        decoration: BoxDecoration(
          color: AppColors.dangerSoft,
          borderRadius: BorderRadius.circular(18),
        ),
        child: const Icon(Icons.delete_outline_rounded,
            color: AppColors.danger),
      ),
      onDismissed: (_) {
        prov.delete(item);
        showToast(context, 'Notification deleted');
      },
      child: MCard(
        padding: const EdgeInsets.all(14),
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
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: item.isRead ? AppColors.paper : Colors.white,
                borderRadius: BorderRadius.circular(13),
              ),
              child: const Icon(Icons.medication_rounded,
                  color: AppColors.primary, size: 22),
            ),
            const SizedBox(width: 12),
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
                            fontSize: 14.5,
                            fontWeight:
                            item.isRead ? FontWeight.w600 : FontWeight.w700,
                            color: AppColors.ink,
                          ),
                        ),
                      ),
                      if (!item.isRead)
                        Container(
                          width: 8,
                          height: 8,
                          margin: const EdgeInsets.only(left: 8, top: 3),
                          decoration: const BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    item.message,
                    style: const TextStyle(
                        fontSize: 12.5, color: AppColors.muted, height: 1.35),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      MChip(item.date,
                          icon: Icons.event_rounded,
                          background: AppColors.paper,
                          foreground: AppColors.inkSoft),
                      const SizedBox(width: 6),
                      MChip(item.time,
                          icon: Icons.schedule_rounded,
                          background: AppColors.paper,
                          foreground: AppColors.inkSoft),
                      const Spacer(),
                      if (item.isRead)
                        const Icon(Icons.done_all_rounded,
                            size: 16, color: AppColors.muted)
                      else
                        const Icon(Icons.fiber_manual_record_rounded,
                            size: 8, color: AppColors.primary),
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
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      color: AppColors.soft,
                      borderRadius: BorderRadius.circular(28),
                    ),
                    child: const Icon(Icons.notifications_none_rounded,
                        size: 46, color: AppColors.primary),
                  ),
                  const SizedBox(height: 18),
                  Text('No notifications yet.',
                      style: GoogleFonts.sora(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink)),
                  const SizedBox(height: 6),
                  const Text(
                    'Reminders and updates will show up here as they arrive.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: AppColors.muted),
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
            child: CircularProgressIndicator(color: AppColors.primary),
          ),
        ),
      ),
    );
  }
}