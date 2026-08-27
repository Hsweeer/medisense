// lib/features/reminders/add_reminder_category_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_colors.dart';
import '../caregiver/screens/caregiver_requests_screen.dart';
import 'add_reminder_form_screen.dart';
import 'reminder_form_helpers.dart';

/// Shown when the user taps "Add reminder" / "Create new reminder" on the
/// reminders list. Mirrors the app's own onboarding "let's set up your
/// routine" screen — three category cards, each opening a full-screen
/// add-reminder form tailored to that category — plus a fourth "For
/// someone else" card that starts the Caregiver Reminder Sharing flow
/// instead (send/accept a permission request, then create reminders on
/// someone else's account).
class AddReminderCategoryScreen extends StatelessWidget {
  const AddReminderCategoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // One extra slot at the end for the "For someone else" card, which
    // isn't part of ReminderCategory since it routes to a different flow
    // (caregiver permission + recipient picker) rather than the standard
    // add-reminder form.
    final itemCount = ReminderCategory.values.length + 1;

    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        backgroundColor: AppColors.paper,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.close_rounded, color: AppColors.ink, size: 24.sp),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(20.w, 4.h, 20.w, 20.h),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Let's set up a reminder!",
                style: GoogleFonts.sora(
                  fontSize: 23.sp,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                ),
              ),
              SizedBox(height: 6.h),
              Text(
                'Choose a category to get started.',
                style: TextStyle(fontSize: 14.sp, color: AppColors.muted),
              ),
              SizedBox(height: 22.h),
              Expanded(
                child: ListView.separated(
                  physics: const BouncingScrollPhysics(),
                  itemCount: itemCount,
                  separatorBuilder: (_, _) => SizedBox(height: 14.h),
                  itemBuilder: (ctx, i) {
                    // Last slot: the caregiver card, styled to match the
                    // three category cards above it.
                    if (i == ReminderCategory.values.length) {
                      return _CaregiverCard(
                        onTap: () {
                          // Route through the caregiver hub: it shows any
                          // already-accepted recipients (with a button
                          // straight into CreateCaregiverReminderScreen) and
                          // lets the user send a new request if they don't
                          // have one yet — this used to jump straight to the
                          // search screen every time, which meant there was
                          // no way back in to actually create a reminder
                          // once a request was accepted.
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const CaregiverRequestsScreen(),
                            ),
                          );
                        },
                      );
                    }

                    final cat = ReminderCategory.values[i];
                    return _CategoryCard(
                      category: cat,
                      onTap: () async {
                        final saved = await Navigator.of(context).push<bool>(
                          MaterialPageRoute(
                            builder: (_) =>
                                AddReminderFormScreen(category: cat),
                          ),
                        );
                        // Bubble the "saved" result straight back to the
                        // reminders list — no need to linger on the
                        // category picker once a reminder was created.
                        if (saved == true && context.mounted) {
                          Navigator.of(context).pop();
                        }
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({required this.category, required this.onTap});

  final ReminderCategory category;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: EdgeInsets.all(16.r),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(20.r),
          border: Border.all(
            color: category.color.withValues(alpha: .22),
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 54.r,
              height: 54.r,
              decoration: BoxDecoration(
                color: category.softColor,
                borderRadius: BorderRadius.circular(16.r),
              ),
              alignment: Alignment.center,
              child: Icon(category.icon, color: category.color, size: 26.sp),
            ),
            SizedBox(width: 14.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    category.label,
                    style: GoogleFonts.sora(
                      fontSize: 15.5.sp,
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink,
                    ),
                  ),
                  SizedBox(height: 4.h),
                  Text(
                    category.description,
                    style: TextStyle(
                      fontSize: 12.sp,
                      color: AppColors.muted,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: 8.w),
            Container(
              width: 30.r,
              height: 30.r,
              margin: EdgeInsets.only(top: 2.h),
              decoration: BoxDecoration(
                color: category.softColor,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.add_rounded,
                color: category.color,
                size: 18.sp,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Fourth card, visually identical to [_CategoryCard] but not backed by
/// [ReminderCategory] since it opens the Caregiver Reminder Sharing flow
/// (contact search / request / accept) instead of the standard add-form.
/// Uses AppColors.ai (violet) so it reads as distinct from the three
/// personal-reminder categories above it.
class _CaregiverCard extends StatelessWidget {
  const _CaregiverCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 54.r,
              height: 54.r,
              decoration: BoxDecoration(
                color: AppColors.aiSoft,
                borderRadius: BorderRadius.circular(16.r),
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.people_alt_rounded,
                color: AppColors.ai,
                size: 26.sp,
              ),
            ),
            SizedBox(width: 14.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'For someone else',
                    style: GoogleFonts.sora(
                      fontSize: 15.5.sp,
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink,
                    ),
                  ),
                  SizedBox(height: 4.h),
                  Text(
                    'Create a reminder on a family member or friend\'s '
                        'account, with their permission.',
                    style: TextStyle(
                      fontSize: 12.sp,
                      color: AppColors.muted,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: 8.w),
            Container(
              width: 30.r,
              height: 30.r,
              margin: EdgeInsets.only(top: 2.h),
              decoration: BoxDecoration(
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