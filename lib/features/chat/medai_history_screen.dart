import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/shared_widgets.dart';
import '../../data/models/models.dart';
import '../../providers/chat_provider.dart';

/// Lists the logged-in user's saved MedAI conversations — tap one to
/// reopen it, or start a new chat. Every conversation here belongs only to
/// the current user; nothing is shared across accounts.
class MedAiHistoryScreen extends StatefulWidget {
  const MedAiHistoryScreen({super.key});

  @override
  State<MedAiHistoryScreen> createState() => _MedAiHistoryScreenState();
}

class _MedAiHistoryScreenState extends State<MedAiHistoryScreen> {
  @override
  void initState() {
    super.initState();
    // Always show the freshest list — a message sent since this screen
    // was last open shouldn't leave a stale preview showing.
    context.read<ChatProvider>().loadConversations();
  }

  String _relativeTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  Future<void> _confirmDelete(ChatConversationSummary convo) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this chat?'),
        content: Text(
            '"${convo.title}" and everything in it will be permanently deleted.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('Delete', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await context.read<ChatProvider>().deleteConversation(convo.id);
    if (mounted) showToast(context, 'Chat deleted');
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatProvider>();

    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        backgroundColor: AppColors.paper,
        surfaceTintColor: AppColors.paper,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: AppColors.ink,
        title: Text('MedAI chats',
            style: TextStyle(fontSize: 16.5.sp, fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
            tooltip: 'New chat',
            icon: Icon(Icons.add_comment_rounded, size: 22.sp),
            onPressed: () async {
              await context.read<ChatProvider>().startNewConversation();
              if (context.mounted) Navigator.of(context).pop();
            },
          ),
        ],
      ),
      body: SafeArea(
        child: chat.loadingConversations && chat.conversations.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : chat.conversations.isEmpty
                ? _EmptyState(onNewChat: () async {
                    await context.read<ChatProvider>().startNewConversation();
                    if (context.mounted) Navigator.of(context).pop();
                  })
                : ListView.separated(
                    padding: EdgeInsets.fromLTRB(20.w, 8.h, 20.w, 20.h),
                    itemCount: chat.conversations.length,
                    separatorBuilder: (_, __) => SizedBox(height: 8.h),
                    itemBuilder: (context, i) {
                      final convo = chat.conversations[i];
                      final isOpen = convo.id == chat.currentConversationId;
                      return MCard(
                        border: isOpen
                            ? Border.all(color: AppColors.primary, width: 1.3.w)
                            : Border.all(color: AppColors.line),
                        onTap: () async {
                          await context
                              .read<ChatProvider>()
                              .openConversation(convo.id);
                          if (context.mounted) Navigator.of(context).pop();
                        },
                        child: Row(
                          children: [
                            Container(
                              width: 38.r,
                              height: 38.r,
                              decoration: BoxDecoration(
                                color: AppColors.aiSoft,
                                borderRadius: BorderRadius.circular(11.r),
                              ),
                              child: Icon(Icons.psychology_alt_rounded,
                                  color: AppColors.ai, size: 19.sp),
                            ),
                            SizedBox(width: 12.w),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(convo.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          fontSize: 14.sp,
                                          fontWeight: FontWeight.w700)),
                                  if (convo.lastMessagePreview.isNotEmpty) ...[
                                    SizedBox(height: 2.h),
                                    Text(convo.lastMessagePreview,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            fontSize: 12.sp,
                                            color: AppColors.muted)),
                                  ],
                                ],
                              ),
                            ),
                            SizedBox(width: 8.w),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(_relativeTime(convo.updatedAt),
                                    style: TextStyle(
                                        fontSize: 10.5.sp, color: AppColors.muted)),
                                SizedBox(height: 6.h),
                                InkWell(
                                  onTap: () => _confirmDelete(convo),
                                  borderRadius: BorderRadius.circular(14.r),
                                  child: Padding(
                                    padding: EdgeInsets.all(2.r),
                                    child: Icon(Icons.delete_outline_rounded,
                                        size: 17.sp, color: AppColors.muted),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onNewChat});
  final VoidCallback onNewChat;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 32.w),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.forum_outlined, size: 44.sp, color: AppColors.muted),
            SizedBox(height: 12.h),
            Text('No saved chats yet',
                style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w700)),
            SizedBox(height: 6.h),
            Text('Start a conversation with MedAI and it will show up here.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5.sp, color: AppColors.muted)),
            SizedBox(height: 18.h),
            PrimaryButton(
                label: 'Start new chat',
                icon: Icons.add_comment_rounded,
                onPressed: onNewChat),
          ],
        ),
      ),
    );
  }
}