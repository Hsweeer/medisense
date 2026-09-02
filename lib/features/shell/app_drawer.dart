import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/shared_widgets.dart';
import '../../providers/auth_provider.dart';
import '../../providers/profile_provider.dart';
import '../notifications/notifications_screen.dart';
import '../profile/edit_profile_screen.dart';
import '../profile/nutrition_history_screen.dart';
import '../profile/prescription_history_screen.dart';
import '../settings/alarm_sound_screen.dart';

/// App-wide navigation drawer — opened from the menu icon on the Home
/// screen. Holds everything that used to live under Profile → "Settings"
/// (Notifications, Alarm sound, Nutrition, Prescription history, Privacy
/// & data, Help & support, Sign out), plus a header linking to the full
/// profile.
class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<ProfileProvider>().profile;
    final email = context.read<AuthProvider>().currentEmail;
    final displayName = profile.name.trim();

    return Drawer(
      backgroundColor: AppColors.paper,
      width: 300.w,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _DrawerHeader(
              name: displayName,
              email: email,
              imageUrl: profile.imageUrl,
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const EditProfileScreen()),
                );
              },
            ),
            SizedBox(height: 8.h),
            Expanded(
              child: ListView(
                padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 4.h),
                children: [
                  _DrawerTile(
                    icon: Icons.notifications_outlined,
                    label: 'Notifications',
                    onTap: () {
                      Navigator.of(context).pop();
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const NotificationsScreen(),
                        ),
                      );
                    },
                  ),
                  _DrawerTile(
                    icon: Icons.alarm_rounded,
                    label: 'Alarm sound',
                    onTap: () {
                      Navigator.of(context).pop();
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const AlarmSoundScreen(),
                        ),
                      );
                    },
                  ),
                  _DrawerTile(
                    icon: Icons.restaurant_rounded,
                    label: 'Nutrition',
                    onTap: () {
                      Navigator.of(context).pop();
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const NutritionHistoryScreen(),
                        ),
                      );
                    },
                  ),
                  _DrawerTile(
                    icon: Icons.receipt_long_rounded,
                    label: 'Prescription history',
                    onTap: () {
                      Navigator.of(context).pop();
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const PrescriptionHistoryScreen(),
                        ),
                      );
                    },
                  ),
                  _DrawerTile(
                    icon: Icons.lock_outline_rounded,
                    label: 'Privacy & data',
                    onTap: () {
                      Navigator.of(context).pop();
                      showToast(context, 'Privacy settings');
                    },
                  ),
                  _DrawerTile(
                    icon: Icons.help_outline_rounded,
                    label: 'Help & support',
                    onTap: () {
                      Navigator.of(context).pop();
                      showToast(context, 'Support center');
                    },
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(vertical: 12.h),
                    child: Divider(height: 1.h, color: AppColors.line),
                  ),
                  _DrawerTile(
                    icon: Icons.logout_rounded,
                    label: 'Sign out',
                    color: AppColors.danger,
                    onTap: () async {
                      final confirmed = await AppDialog.confirm(
                        context: context,
                        title: 'Sign out?',
                        message:
                            'You will be signed out of your account and need to sign in again to continue.',
                        confirmText: 'Sign out',
                        destructive: true,
                        icon: Icons.logout_rounded,
                      );
                      if (!confirmed || !context.mounted) return;
                      Navigator.of(context).pop();
                      await context.read<AuthProvider>().logout();
                    },
                  ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(20.w, 6.h, 20.w, 16.h),
              child: Text(
                'MediSense',
                style: TextStyle(
                  fontSize: 11.sp,
                  color: AppColors.muted,
                  fontWeight: FontWeight.w600,
                  letterSpacing: .5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Gradient header at the top of the drawer — avatar, name, email, tap to
/// edit the full profile.
class _DrawerHeader extends StatelessWidget {
  const _DrawerHeader({
    required this.name,
    required this.email,
    required this.imageUrl,
    required this.onTap,
  });

  final String name;
  final String email;
  final String? imageUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.fromLTRB(20.w, 20.h, 20.w, 22.h),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: AppColors.gradient,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Row(
          children: [
            InitialsAvatar(name, size: 52.r, imageUrl: imageUrl),
            SizedBox(width: 14.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name.isEmpty ? 'Complete your profile' : name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.sora(
                      fontSize: 16.sp,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(height: 3.h),
                  Text(
                    email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.sp,
                      color: Colors.white.withValues(alpha: .85),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: Colors.white.withValues(alpha: .85),
              size: 22.sp,
            ),
          ],
        ),
      ),
    );
  }
}

/// One row in the drawer's option list — icon, label, chevron.
class _DrawerTile extends StatelessWidget {
  const _DrawerTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color = AppColors.ink,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14.r),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 12.h),
          child: Row(
            children: [
              Icon(
                icon,
                color: color == AppColors.ink ? AppColors.inkSoft : color,
                size: 22.sp,
              ),
              SizedBox(width: 16.w),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 14.5.sp,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: AppColors.muted,
                size: 19.sp,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
