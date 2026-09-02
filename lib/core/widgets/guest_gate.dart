// PATH: lib/core/widgets/guest_gate.dart
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../features/auth/login_screen.dart';
import '../../providers/auth_provider.dart';
import '../theme/app_colors.dart';

/// Call this at the top of any action that needs a real account
/// (saving a reminder, editing the health profile, starting SOS
/// tracking, etc). If the current user is just browsing in guest
/// mode, it shows a "Login required" sheet and returns `false` so
/// the caller can bail out. If the user is already signed in, it
/// returns `true` immediately with no UI shown.
///
/// Usage:
/// ```dart
/// onPressed: () async {
///   if (!await requireLogin(context, feature: 'save a reminder')) return;
///   _openAddReminderFlow(context);
/// }
/// ```
Future<bool> requireLogin(
  BuildContext context, {
  required String feature,
}) async {
  final isGuest = context.read<AuthProvider>().isGuest;
  if (!isGuest) return true;

  final proceed = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (sheetContext) => _LoginRequiredSheet(feature: feature),
  );
  return proceed ?? false;
}

class _LoginRequiredSheet extends StatelessWidget {
  const _LoginRequiredSheet({required this.feature});

  final String feature;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        margin: EdgeInsets.all(12.r),
        padding: EdgeInsets.fromLTRB(20.w, 22.h, 20.w, 18.h),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24.r),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 48.r,
              height: 48.r,
              decoration: BoxDecoration(
                color: AppColors.soft,
                borderRadius: BorderRadius.circular(14.r),
              ),
              child: Icon(
                Icons.lock_outline_rounded,
                color: AppColors.primary,
                size: 24.sp,
              ),
            ),
            SizedBox(height: 14.h),
            Text(
              'Login required',
              style: GoogleFonts.sora(
                fontSize: 18.sp,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(height: 6.h),
            Text(
              'You\'re browsing as a guest. Please create a free account or '
              'log in to $feature.',
              style: TextStyle(
                fontSize: 13.5.sp,
                color: AppColors.muted,
                height: 1.4,
              ),
            ),
            SizedBox(height: 20.h),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(vertical: 14.h),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14.r),
                  ),
                ),
                onPressed: () {
                  Navigator.of(context).pop(false);
                  context.read<AuthProvider>().exitGuestMode();
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                    (route) => false,
                  );
                },
                child: Text(
                  'Login / Sign up',
                  style: TextStyle(
                    fontSize: 14.5.sp,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            SizedBox(height: 8.h),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(
                  'Not now',
                  style: TextStyle(
                    fontSize: 13.5.sp,
                    color: AppColors.muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small reusable banner to show at the top of screens that ARE visible
/// to guests but contain some locked/limited functionality — e.g. Home,
/// Nearby, or the AI chat. Tapping it takes the user straight to login.
class GuestModeBanner extends StatelessWidget {
  const GuestModeBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        context.read<AuthProvider>().exitGuestMode();
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
      },
      child: Container(
        width: double.infinity,
        margin: EdgeInsets.only(bottom: 12.h),
        padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.h),
        decoration: BoxDecoration(
          color: AppColors.soft,
          borderRadius: BorderRadius.circular(14.r),
          border: Border.all(color: AppColors.primary.withValues(alpha: .24)),
        ),
        child: Row(
          children: [
            Icon(
              Icons.person_outline_rounded,
              color: AppColors.primary,
              size: 18.sp,
            ),
            SizedBox(width: 8.w),
            Expanded(
              child: Text(
                'Browsing as guest — login to save your data',
                style: TextStyle(
                  fontSize: 12.sp,
                  fontWeight: FontWeight.w600,
                  color: AppColors.onSoft,
                ),
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: AppColors.primary,
              size: 18.sp,
            ),
          ],
        ),
      ),
    );
  }
}
