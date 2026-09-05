import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_colors.dart';
import 'add_reminder_form_screen.dart';
import 'reminder_form_helpers.dart';

/// The "For you" branch of the add-reminder flow — the four personal
/// categories (Medications / Measurements / Activities / Check-ups),
/// each opening a full-screen add-reminder form tailored to that
/// category. Split out of [AddReminderCategoryScreen] so the "for
/// someone else" flow can live entirely on its own screen instead of
/// being a fifth card in this list.
class ForYouCategoryScreen extends StatelessWidget {
  const ForYouCategoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        backgroundColor: AppColors.paper,
        elevation: 0,
        title: Text(
          'For you',
          style: GoogleFonts.sora(
            fontSize: 17.sp,
            fontWeight: FontWeight.w800,
            color: AppColors.ink,
          ),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(20.w, 4.h, 20.w, 20.h),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Choose a category to get started.',
                style: TextStyle(fontSize: 14.sp, color: AppColors.muted),
              ),
              SizedBox(height: 22.h),
              Expanded(
                child: ListView.separated(
                  physics: const BouncingScrollPhysics(),
                  itemCount: ReminderCategory.values.length,
                  separatorBuilder: (_, _) => SizedBox(height: 14.h),
                  itemBuilder: (ctx, i) {
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
                        // "who is this for" screen so it can pop too, and
                        // the reminders list reflects the brand-new card
                        // immediately.
                        if (saved == true && context.mounted) {
                          Navigator.of(context).pop(true);
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
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          category.label,
                          style: GoogleFonts.sora(
                            fontSize: 15.5.sp,
                            fontWeight: FontWeight.w800,
                            color: AppColors.ink,
                          ),
                        ),
                      ),
                      SizedBox(width: 8.w),
                      Container(
                        width: 30.r,
                        height: 30.r,
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
          ],
        ),
      ),
    );
  }
}
