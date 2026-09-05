import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/services/caregiver_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/shared_widgets.dart';
import '../../data/models/caregiver_models.dart';
import '../caregiver/screens/add_caregiver_screen.dart';
import '../caregiver/screens/create_caregiver_reminder_screen.dart';

/// The "For someone else" branch of the add-reminder flow. Unlike the old
/// single flat caregiver card, this is its own dedicated screen: a small
/// pending-requests badge up top (so an incoming request never gets
/// missed), and — front and center — the direct, tappable list of people
/// already accepted as recipients. Tapping a person jumps straight into
/// [CreateCaregiverReminderScreen] with them preselected, so setting a
/// reminder for someone is exactly two taps once they're connected.
class ForSomeoneElseScreen extends StatelessWidget {
  const ForSomeoneElseScreen({super.key});

  void _openAddCaregiver(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const AddCaregiverScreen()));
  }

  Future<void> _openRecipient(BuildContext context, CaregiverLink link) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CreateCaregiverReminderScreen(
          initialRecipientUid: link.recipientUid,
        ),
      ),
    );
    if (saved == true && context.mounted) {
      Navigator.of(context).pop(true);
    }
  }

  void _openPendingSheet(BuildContext context, List<CaregiverLink> requests) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      elevation: 0,
      builder: (_) => _PendingSheet(requests: requests),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        backgroundColor: AppColors.paper,
        elevation: 0,
        title: Text(
          'For someone else',
          style: GoogleFonts.sora(
            fontSize: 17.sp,
            fontWeight: FontWeight.w800,
            color: AppColors.ink,
          ),
        ),
        actions: [
          StreamBuilder<List<CaregiverLink>>(
            stream: CaregiverService.instance.incomingRequests(),
            builder: (context, snapshot) {
              final requests = snapshot.data ?? const [];
              return Padding(
                padding: EdgeInsets.only(right: 14.w),
                child: _PendingBadge(
                  count: requests.length,
                  onTap: () => _openPendingSheet(context, requests),
                ),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: StreamBuilder<List<CaregiverLink>>(
          stream: CaregiverService.instance.myAcceptedRecipients(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final links = snapshot.data!;

            if (links.isEmpty) {
              return _EmptyState(onInvite: () => _openAddCaregiver(context));
            }

            return ListView(
              padding: EdgeInsets.fromLTRB(20.w, 4.h, 20.w, 24.h),
              children: [
                Text(
                  'Choose who this reminder is for.',
                  style: TextStyle(fontSize: 14.sp, color: AppColors.muted),
                ),
                SizedBox(height: 18.h),
                for (final link in links) ...[
                  _RecipientCard(
                    link: link,
                    onTap: () => _openRecipient(context, link),
                  ),
                  SizedBox(height: 12.h),
                ],
                SizedBox(height: 10.h),
                _InviteAnotherRow(onTap: () => _openAddCaregiver(context)),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Small round icon in the app bar showing how many caregiver requests
/// are waiting — a quiet reminder that doesn't interrupt the main "pick a
/// recipient" flow below it, but is never more than one tap away.
class _PendingBadge extends StatelessWidget {
  const _PendingBadge({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: count > 0 ? AppColors.warningSoft : AppColors.soft,
      borderRadius: BorderRadius.circular(14.r),
      child: InkWell(
        borderRadius: BorderRadius.circular(14.r),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.all(9.r),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(
                Icons.hourglass_top_rounded,
                color: count > 0 ? AppColors.warning : AppColors.primary,
                size: 20.sp,
              ),
              if (count > 0)
                Positioned(
                  top: -4.h,
                  right: -4.w,
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: 4.w,
                      vertical: 1.h,
                    ),
                    constraints: BoxConstraints(minWidth: 15.r),
                    decoration: BoxDecoration(
                      color: AppColors.danger,
                      borderRadius: BorderRadius.circular(99.r),
                      border: Border.all(color: AppColors.paper, width: 1.5.w),
                    ),
                    child: Text(
                      '$count',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 9.sp,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One accepted recipient, rendered as a large tappable card (name +
/// avatar initial + a clear "set a reminder" call to action) so the whole
/// "for someone else" screen reads as a person-picker, not a settings
/// list.
class _RecipientCard extends StatelessWidget {
  const _RecipientCard({required this.link, required this.onTap});

  final CaregiverLink link;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final initial = link.recipientName.isNotEmpty
        ? link.recipientName[0].toUpperCase()
        : '?';

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: EdgeInsets.all(16.r),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(20.r),
          border: Border.all(
            color: AppColors.ai.withValues(alpha: .22),
            width: 1.3.w,
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.ink.withValues(alpha: .04),
              blurRadius: 14.r,
              offset: Offset(0, 4.h),
            ),
          ],
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 26.r,
              backgroundColor: AppColors.aiSoft,
              child: Text(
                initial,
                style: TextStyle(
                  fontSize: 18.sp,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ai,
                ),
              ),
            ),
            SizedBox(width: 14.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    link.recipientName,
                    style: GoogleFonts.sora(
                      fontSize: 15.5.sp,
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink,
                    ),
                  ),
                  SizedBox(height: 3.h),
                  Text(
                    'Tap to set a reminder for them',
                    style: TextStyle(fontSize: 12.sp, color: AppColors.muted),
                  ),
                ],
              ),
            ),
            Container(
              width: 32.r,
              height: 32.r,
              decoration: const BoxDecoration(
                color: AppColors.aiSoft,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(Icons.add_rounded, color: AppColors.ai, size: 18.sp),
            ),
          ],
        ),
      ),
    );
  }
}

/// Trailing row offering to invite one more caregiver connection — kept
/// low-key (a text row, not a full CTA card) since the primary action on
/// this screen is picking someone already connected.
class _InviteAnotherRow extends StatelessWidget {
  const _InviteAnotherRow({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 14.h, horizontal: 16.w),
        decoration: BoxDecoration(
          color: AppColors.soft,
          borderRadius: BorderRadius.circular(16.r),
          border: Border.all(color: AppColors.primary.withValues(alpha: .18)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.person_add_alt_1_rounded,
              size: 18.sp,
              color: AppColors.primary,
            ),
            SizedBox(width: 8.w),
            Text(
              'Connect with someone else',
              style: TextStyle(
                fontSize: 13.5.sp,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown when the account has no accepted caregiver recipients yet —
/// explains the flow in one line and gets straight to the "Invite"
/// action, since there's nothing to pick from otherwise.
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onInvite});

  final VoidCallback onInvite;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 28.w),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 76.r,
              height: 76.r,
              decoration: const BoxDecoration(
                color: AppColors.aiSoft,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.people_alt_rounded,
                color: AppColors.ai,
                size: 34.sp,
              ),
            ),
            SizedBox(height: 18.h),
            Text(
              'No one connected yet',
              style: GoogleFonts.sora(
                fontSize: 17.sp,
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
              ),
            ),
            SizedBox(height: 8.h),
            Text(
              'Invite a family member or friend and, once they accept, '
              'they\'ll show up right here so you can set reminders for them.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.sp,
                color: AppColors.muted,
                height: 1.5,
              ),
            ),
            SizedBox(height: 22.h),
            PrimaryButton(
              label: 'Invite caregiver',
              icon: Icons.person_add_alt_1_rounded,
              onPressed: onInvite,
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet listing incoming caregiver requests, with accept/decline
/// actions — a self-contained copy of the pattern used on the caregiver
/// hub screen, so this screen doesn't need to depend on it.
class _PendingSheet extends StatelessWidget {
  const _PendingSheet({required this.requests});

  final List<CaregiverLink> requests;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75,
      ),
      decoration: const BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(20.w, 12.h, 20.w, 20.h),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SheetHandle(),
              SizedBox(height: 18.h),
              SheetHeader(
                icon: Icons.hourglass_top_rounded,
                color: AppColors.warning,
                title: 'Pending requests',
                subtitle: 'People who want to manage your reminders.',
              ),
              SizedBox(height: 18.h),
              Flexible(
                child: SingleChildScrollView(
                  child: requests.isEmpty
                      ? Padding(
                          padding: EdgeInsets.symmetric(vertical: 20.h),
                          child: Text(
                            'No pending requests.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13.sp,
                              color: AppColors.muted,
                            ),
                          ),
                        )
                      : Column(
                          children: requests.map((r) {
                            return Container(
                              margin: EdgeInsets.only(bottom: 10.h),
                              padding: EdgeInsets.all(12.r),
                              decoration: BoxDecoration(
                                color: AppColors.paper,
                                borderRadius: BorderRadius.circular(16.r),
                                border: Border.all(
                                  color: AppColors.line.withValues(alpha: .7),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 42.r,
                                    height: 42.r,
                                    decoration: BoxDecoration(
                                      color: AppColors.warningSoft,
                                      borderRadius: BorderRadius.circular(13.r),
                                    ),
                                    alignment: Alignment.center,
                                    child: Icon(
                                      Icons.person_add_alt_1_rounded,
                                      color: AppColors.warning,
                                      size: 20.sp,
                                    ),
                                  ),
                                  SizedBox(width: 12.w),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          r.senderName,
                                          style: TextStyle(
                                            fontSize: 14.sp,
                                            fontWeight: FontWeight.w700,
                                            color: AppColors.ink,
                                          ),
                                        ),
                                        SizedBox(height: 1.h),
                                        Text(
                                          'Wants to manage your reminders',
                                          style: TextStyle(
                                            fontSize: 11.5.sp,
                                            color: AppColors.muted,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      _RoundIconAction(
                                        icon: Icons.close_rounded,
                                        color: AppColors.danger,
                                        background: AppColors.dangerSoft,
                                        onTap: () => CaregiverService.instance
                                            .respondToRequest(
                                              r.id,
                                              accept: false,
                                            ),
                                      ),
                                      SizedBox(width: 8.w),
                                      _RoundIconAction(
                                        icon: Icons.check_rounded,
                                        color: AppColors.success,
                                        background: AppColors.successSoft,
                                        onTap: () => CaregiverService.instance
                                            .respondToRequest(
                                              r.id,
                                              accept: true,
                                            ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoundIconAction extends StatelessWidget {
  const _RoundIconAction({
    required this.icon,
    required this.color,
    required this.background,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final Color background;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.all(8.r),
          child: Icon(icon, color: color, size: 18.sp),
        ),
      ),
    );
  }
}
