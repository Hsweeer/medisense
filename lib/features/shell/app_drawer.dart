import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/guest_gate.dart';
import '../../core/widgets/shared_widgets.dart';
import '../../providers/auth_provider.dart';
import '../../providers/profile_provider.dart';
import '../notifications/notifications_screen.dart';
import '../profile/edit_profile_screen.dart';
import '../profile/nutrition_history_screen.dart';
import '../profile/prescription_history_screen.dart';
import '../settings/alarm_sound_screen.dart';
import '../skin/skin_history_screen.dart';
import '../vitals/vitals_history_screen.dart';

/// App-wide navigation drawer — opened from the menu icon on the Home
/// screen. Holds everything that used to live under Profile → "Settings"
/// (Notifications, Alarm sound, Nutrition, Prescription history, Privacy
/// & data, Help & support, Sign out), plus a "complete your profile" hero
/// card up top linking to the full profile editor.
class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: AppColors.paper,
      width: 320.w,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 4.h),
              child: _ProfileHeroCard(
                onTap: () async {
                  // Same login gate as every other profile-editing entry
                  // point — the drawer's own header shouldn't be a
                  // shortcut around it for guests.
                  final drawerContext = context;
                  if (!await requireLogin(
                    drawerContext,
                    feature: 'view your profile',
                  )) {
                    return;
                  }
                  if (!drawerContext.mounted) return;
                  Navigator.of(drawerContext).pop();
                  Navigator.of(drawerContext).push(
                    MaterialPageRoute(
                      builder: (_) => const EditProfileScreen(),
                    ),
                  );
                },
              ),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 4.h),
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
                    icon: Icons.face_retouching_natural_rounded,
                    label: 'Skin check history',
                    onTap: () {
                      Navigator.of(context).pop();
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const SkinHistoryScreen(),
                        ),
                      );
                    },
                  ),
                  _DrawerTile(
                    icon: Icons.favorite_border_rounded,
                    label: 'Heart rate history',
                    onTap: () {
                      Navigator.of(context).pop();
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const VitalsHistoryScreen(),
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
                  SizedBox(height: 10.h),
                  _DrawerTile(
                    icon: Icons.help_outline_rounded,
                    label: 'Help & support',
                    onTap: () {
                      Navigator.of(context).pop();
                      showToast(context, 'Support center');
                    },
                    showDivider: false,
                  ),
                  SizedBox(height: 14.h),
                  // Sign out — its own outlined card, echoing the
                  // highlighted Privacy & data tile but in red.
                  _HighlightTile(
                    icon: Icons.logout_rounded,
                    title: 'Sign out',
                    subtitle: 'Log out from your account',
                    color: AppColors.danger,
                    background: AppColors.dangerSoft,
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
                  SizedBox(height: 8.h),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(16.w, 4.h, 16.w, 16.h),
              child: const _DrawerFooterCard(),
            ),
          ],
        ),
      ),
    );
  }
}

/// Teal gradient "complete your profile" hero card at the top of the
/// drawer — avatar circle, title/subtitle, a progress bar with percentage,
/// and a white circular arrow button, all tappable to open the profile
/// editor. A couple of faint crosses in the corner echo the app's medical
/// motif without competing with the text.
class _ProfileHeroCard extends StatelessWidget {
  const _ProfileHeroCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<ProfileProvider>().profile;
    final displayName = profile.name.trim();

    return InkWell(
      borderRadius: BorderRadius.circular(22.r),
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.all(18.r),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: AppColors.gradient,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(22.r),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: .28),
              blurRadius: 18.r,
              offset: Offset(0, 8.h),
            ),
          ],
        ),
        child: Stack(
          children: [
            // Faint corner crosses — decorative only.
            Positioned(
              top: -6,
              right: 46,
              child: _MiniCross(size: 14, opacity: .18),
            ),
            Positioned(
              bottom: 6,
              left: -4,
              child: _MiniCross(size: 12, opacity: .14),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 56.r,
                      height: 56.r,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child:
                          profile.imageUrl != null &&
                              profile.imageUrl!.isNotEmpty
                          ? ClipOval(
                              child: Image.network(
                                profile.imageUrl!,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => Icon(
                                  Icons.person_rounded,
                                  color: AppColors.primary,
                                  size: 30.sp,
                                ),
                              ),
                            )
                          : Icon(
                              Icons.person_rounded,
                              color: AppColors.primary,
                              size: 30.sp,
                            ),
                    ),
                    SizedBox(width: 14.w),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            displayName.isEmpty
                                ? 'Complete your profile'
                                : displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.sora(
                              fontSize: 17.sp,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(height: 3.h),
                          Text(
                            'Add your details for better health insights',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.5.sp,
                              height: 1.3,
                              color: Colors.white.withValues(alpha: .88),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(width: 8.w),
                    Container(
                      width: 40.r,
                      height: 40.r,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.arrow_forward_rounded,
                        color: AppColors.primary,
                        size: 20.sp,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniCross extends StatelessWidget {
  const _MiniCross({required this.size, required this.opacity});
  final double size;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity,
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _CrossPainter(color: Colors.white)),
      ),
    );
  }
}

class _CrossPainter extends CustomPainter {
  _CrossPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;
    final c = Offset(size.width / 2, size.height / 2);
    canvas.drawLine(
      Offset(c.dx - size.width / 2, c.dy),
      Offset(c.dx + size.width / 2, c.dy),
      paint,
    );
    canvas.drawLine(
      Offset(c.dx, c.dy - size.height / 2),
      Offset(c.dx, c.dy + size.height / 2),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// One plain row in the drawer's option list — icon in a soft rounded
/// badge, label, chevron, with a thin divider under it (unless it's the
/// last item in its group).
class _DrawerTile extends StatelessWidget {
  const _DrawerTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.showDivider = true,
  }) : color = AppColors.ink;

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(14.r),
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 12.h),
              child: Row(
                children: [
                  Container(
                    width: 38.r,
                    height: 38.r,
                    decoration: BoxDecoration(
                      color: AppColors.soft,
                      borderRadius: BorderRadius.circular(11.r),
                    ),
                    child: Icon(
                      icon,
                      color: color == AppColors.ink ? AppColors.primary : color,
                      size: 19.sp,
                    ),
                  ),
                  SizedBox(width: 14.w),
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 14.5.sp,
                        fontWeight: FontWeight.w700,
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
        ),
        if (showDivider)
          Divider(height: 1.h, color: AppColors.line, indent: 52.w),
      ],
    );
  }
}

/// A tile that stands out from the plain list — its own rounded card with
/// a soft background, a two-line label (title + subtitle), and an icon
/// badge tinted the same color as the text. Used for "Privacy & data"
/// (teal) and "Sign out" (red), matching the reference design.
class _HighlightTile extends StatelessWidget {
  const _HighlightTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.color = AppColors.primary,
    this.background = AppColors.soft,
  }) : borderColor = null;

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Color color;
  final Color background;

  /// Optional border tint — defaults to a soft tint of [color] so the
  /// card reads as clearly bounded against the plain list rows around
  /// it, matching the outlined look in the reference design.
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      // clipBehavior is the actual fix: without it, Container's
      // borderRadius only affects how its own decoration is painted —
      // it does NOT clip children, so the InkWell's square ripple (and
      // the transparent Material's own paint layer) could still show
      // past the rounded corners as a faint square "background" edge.
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(
          color: (borderColor ?? color).withValues(alpha: .22),
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 14.h),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 42.r,
                  height: 42.r,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .7),
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                  child: Icon(icon, color: color, size: 20.sp),
                ),
                SizedBox(width: 14.w),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 14.5.sp,
                          fontWeight: FontWeight.w800,
                          color: color == AppColors.primary
                              ? AppColors.ink
                              : color,
                        ),
                      ),
                      SizedBox(height: 3.h),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 11.5.sp,
                          color: AppColors.muted,
                          height: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: color, size: 19.sp),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Small branded footer card — logo mark, wordmark, tagline, and a shield
/// glyph, sitting on a very light teal card at the bottom of the drawer.
class _DrawerFooterCard extends StatelessWidget {
  const _DrawerFooterCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
      decoration: BoxDecoration(
        color: AppColors.soft,
        borderRadius: BorderRadius.circular(16.r),
      ),
      child: Row(
        children: [
          Container(
            width: 36.r,
            height: 36.r,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: AppColors.gradient,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(10.r),
            ),
            child: Icon(
              Icons.favorite_rounded,
              color: Colors.white,
              size: 17.sp,
            ),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'MediSense',
                  style: GoogleFonts.sora(
                    fontSize: 13.5.sp,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                  ),
                ),
                Text(
                  'Your Health. Our Priority.',
                  style: TextStyle(fontSize: 10.5.sp, color: AppColors.muted),
                ),
              ],
            ),
          ),
          Icon(
            Icons.shield_outlined,
            color: AppColors.primary.withValues(alpha: .5),
            size: 20.sp,
          ),
        ],
      ),
    );
  }
}
