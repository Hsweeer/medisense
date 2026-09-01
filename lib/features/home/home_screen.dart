// lib/features/home/home_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_loading.dart';
import '../../core/widgets/shared_widgets.dart';
import '../../providers/location_provider.dart';
import '../../providers/notification_provider.dart';
import '../../providers/profile_provider.dart';
import '../../providers/reminder_provider.dart';
import '../../services/vitals_firestore_service.dart';
import '../caregiver/screens/caregiver_requests_screen.dart';
import '../food_scanner/screens/food_scanner_screen.dart';
import '../nearby/nearby_screen.dart';
import '../notifications/notifications_screen.dart';
import '../prescription/prescription_scanner_screen.dart';
import '../reminders/reminders_screen.dart';
import '../skin/skin_check_screen.dart';
import '../vitals/vitals_history_screen.dart';
import '../vitals/vitals_scan_screen.dart';

/// Home — "what do I need to do right now?"
/// The next-dose card is the hero, everything else sits below it.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final reminders = context.watch<ReminderProvider>();
    final profileProvider = context.watch<ProfileProvider>();
    final profile = profileProvider.profile;
    final next = reminders.nextDose;
    final displayName = profile.name.trim();
    final firstName = displayName.isEmpty
        ? 'there'
        : displayName.split(' ').first;

    return SafeArea(
      child: ListView(
        padding: EdgeInsets.fromLTRB(20.w, 12.h, 20.w, 90.h),
        children: [
          // Greeting bar
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Good morning, $firstName 👋',
                      style: Theme.of(
                        context,
                      ).textTheme.headlineSmall?.copyWith(fontSize: 22.sp),
                    ),
                    const _LocationLabel(),
                  ],
                ),
              ),
              const _NotificationBell(),
              SizedBox(width: 10.w),
              InitialsAvatar(displayName, imageUrl: profile.imageUrl),
            ],
          ),
          SizedBox(height: 16.h),
          // Universal search → nearby care
          TextField(
            readOnly: true,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const NearbyScreen(showBack: true),
              ),
            ),
            decoration: InputDecoration(
              hintText: 'Search hospitals, pharmacies…',
              hintStyle: TextStyle(fontSize: 14.sp),
              prefixIcon: Icon(
                Icons.search_rounded,
                color: AppColors.muted,
                size: 22.sp,
              ),
              contentPadding: EdgeInsets.symmetric(vertical: 12.h),
            ),
          ),
          SizedBox(height: 16.h),
          // HERO — next dose card
          GestureDetector(
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const RemindersScreen())),
            child: Container(
              padding: EdgeInsets.all(18.r),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: AppColors.gradient,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20.r),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: .35),
                    blurRadius: 18.r,
                    offset: Offset(0, 8.h),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 48.r,
                    height: 48.r,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .2),
                      borderRadius: BorderRadius.circular(14.r),
                    ),
                    child: Icon(
                      Icons.medication_rounded,
                      color: Colors.white,
                      size: 26.sp,
                    ),
                  ),
                  SizedBox(width: 14.w),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          next == null ? 'ALL DONE TODAY' : 'NEXT DOSE',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: .8),
                            fontSize: 11.sp,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.2,
                          ),
                        ),
                        SizedBox(height: 3.h),
                        Text(
                          next == null
                              ? 'Great job — streak safe 🔥'
                              : '${next.title} · ${next.time}',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16.sp,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (next != null)
                          Text(
                            next.dose,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: .85),
                              fontSize: 12.5.sp,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: Colors.white,
                    size: 24.sp,
                  ),
                ],
              ),
            ),
          ),
          SizedBox(height: 16.h),
          // Quick actions — a 2-2-2 grid. IntrinsicHeight + stretch makes
          // both cards in each row match the height of whichever one has
          // more content (e.g. a longer subtitle), instead of each card
          // hugging its own text and ending up a different size than its
          // neighbor.
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _QuickTile(
                    icon: Icons.alarm_rounded,
                    label: 'My reminders',
                    sub: '${reminders.reminders.length} active',
                    color: AppColors.primary,
                    soft: AppColors.soft,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const RemindersScreen(),
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: _QuickTile(
                    icon: Icons.camera_alt_rounded,
                    label: 'Scan food',
                    sub: 'Check nutrition',
                    color: AppColors.warning,
                    soft: AppColors.warningSoft,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const FoodScannerScreen(),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 12.h),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _QuickTile(
                    icon: Icons.receipt_long_rounded,
                    label: 'Scan prescription',
                    sub: 'Read meds & doses',
                    color: AppColors.ai,
                    soft: AppColors.aiSoft,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const PrescriptionScannerScreen(),
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: _QuickTile(
                    icon: Icons.favorite_rounded,
                    label: 'Heart scan',
                    sub: 'Estimate BPM',
                    color: AppColors.danger,
                    soft: AppColors.dangerSoft,
                    onTap: () => _startHeartScan(context),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 12.h),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _QuickTile(
                    icon: Icons.face_retouching_natural_rounded,
                    label: 'Skin check',
                    sub: 'Visual estimate',
                    color: AppColors.success,
                    soft: AppColors.successSoft,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const SkinCheckScreen(),
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: _QuickTile(
                    icon: Icons.people_alt_rounded,
                    label: 'Caregivers',
                    sub: 'Manage access',
                    color: AppColors.primary,
                    soft: AppColors.soft,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const CaregiverRequestsScreen(),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 20.h),
          // Real AI-personalized advice — generated from the user's
          // health profile + what MedAI has learned from chat, cached
          // and periodically refreshed (see ProfileProvider.forYouTip).
          _ForYouSection(profile: profileProvider),
        ],
      ),
    );
  }
}

/// Launches the vitals (heart-rate) scan, shows the reading it produces
/// (the scan screen itself already displays the result before returning
/// it here), then explicitly asks before saving it to history — unlike
/// the chat flow, which auto-saves every reading.
Future<void> _startHeartScan(BuildContext context) async {
  final bpm = await Navigator.of(context).push<double>(
    MaterialPageRoute(builder: (_) => const VitalsScanScreen()),
  );
  if (bpm == null || !context.mounted) return;

  final shouldSave = await AppDialog.confirm(
    context: context,
    title: 'Save this reading?',
    message: 'Save ${bpm.round()} BPM to your heart-rate history?',
    confirmText: 'Save',
    cancelText: 'Discard',
    icon: Icons.favorite_rounded,
  );

  if (shouldSave != true) return;

  await VitalsFirestoreService.instance.saveScan(bpm);
  if (!context.mounted) return;

  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('Saved to your heart-rate history')),
  );
  Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => const VitalsHistoryScreen()),
  );
}

/// Shows on the home screen. Uses the profile provider's cached, real
/// AI-generated tip (see `ForYouService` + `ProfileProvider.forYouTip`).
/// Falls back to a friendly "add info to unlock this" state until there's
/// enough profile/chat context to personalize on — never shows a fake or
/// generic tip pretending to be personalized.
class _ForYouSection extends StatelessWidget {
  const _ForYouSection({required this.profile});

  final ProfileProvider profile;

  @override
  Widget build(BuildContext context) {
    final tip = profile.forYouTip;
    final loading = profile.forYouLoading;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'For you',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            GestureDetector(
              onTap: loading ? null : () => profile.refreshForYouTip(),
              child: Padding(
                padding: EdgeInsets.all(4.r),
                child: loading
                    ? AppSpinner.inline(size: 15.sp, color: AppColors.primary)
                    : Icon(
                  Icons.refresh_rounded,
                  size: 18.sp,
                  color: AppColors.muted,
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: 6.h),
        MCard(
          color: AppColors.aiSoft,
          border: Border.all(color: AppColors.ai.withValues(alpha: .3)),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38.r,
                height: 38.r,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .6),
                  borderRadius: BorderRadius.circular(12.r),
                ),
                child: Icon(
                  Icons.auto_awesome_rounded,
                  color: AppColors.ai,
                  size: 20.sp,
                ),
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: tip == null
                    ? Text(
                  loading
                      ? 'Personalizing advice for you…'
                      : 'Fill in your health profile or chat with '
                      'MedAI, and personalized advice for your '
                      'situation will show up here.',
                  style: TextStyle(
                    fontSize: 12.5.sp,
                    height: 1.4,
                    color: AppColors.inkSoft,
                  ),
                )
                    : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tip.title,
                      style: TextStyle(
                        fontSize: 14.sp,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 3.h),
                    Text(
                      tip.body,
                      style: TextStyle(
                        fontSize: 12.5.sp,
                        height: 1.4,
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Shows the user's real location once granted; while off, doubles as the
/// control to (re)request it — no separate settings screen needed.
class _LocationLabel extends StatelessWidget {
  const _LocationLabel();

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocationProvider>();
    final showsPin = loc.isGranted || loc.isLoading;

    return GestureDetector(
      onTap: loc.isLoading
          ? null
          : () {
        if (loc.access == LocationAccess.granted) return;
        if (loc.access == LocationAccess.deniedForever ||
            loc.access == LocationAccess.serviceDisabled) {
          loc.openSettings();
        } else {
          loc.requestAccess();
        }
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            showsPin ? Icons.location_on_rounded : Icons.location_off_rounded,
            size: 13.sp,
            color: AppColors.muted,
          ),
          SizedBox(width: 3.w),
          Text(
            loc.displayLabel,
            style: TextStyle(color: AppColors.muted, fontSize: 13.sp),
          ),
        ],
      ),
    );
  }
}

/// Bell icon with an unread-count badge, matching the app's rounded
/// icon-badge language used elsewhere (see _QuickTile below).
class _NotificationBell extends StatelessWidget {
  const _NotificationBell();

  @override
  Widget build(BuildContext context) {
    final unread = context.watch<NotificationProvider>().unreadCount;

    return GestureDetector(
      onTap: () => Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const NotificationsScreen())),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 44.r,
            height: 44.r,
            decoration: BoxDecoration(
              color: AppColors.soft,
              borderRadius: BorderRadius.circular(14.r),
            ),
            child: Icon(
              Icons.notifications_none_rounded,
              color: AppColors.primary,
              size: 22.sp,
            ),
          ),
          if (unread > 0)
            Positioned(
              top: -3.h,
              right: -3.w,
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 5.w, vertical: 2.h),
                constraints: BoxConstraints(minWidth: 18.r),
                decoration: BoxDecoration(
                  color: AppColors.danger,
                  borderRadius: BorderRadius.circular(99.r),
                  border: Border.all(color: AppColors.paper, width: 1.5.w),
                ),
                child: Text(
                  unread > 9 ? '9+' : '$unread',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10.sp,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _QuickTile extends StatelessWidget {
  const _QuickTile({
    required this.icon,
    required this.label,
    required this.sub,
    required this.color,
    required this.soft,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String sub;
  final Color color;
  final Color soft;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MCard(
      onTap: onTap,
      padding: EdgeInsets.all(14.r),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42.r,
            height: 42.r,
            decoration: BoxDecoration(
              color: soft,
              borderRadius: BorderRadius.circular(13.r),
            ),
            child: Icon(icon, color: color, size: 22.sp),
          ),
          SizedBox(height: 10.h),
          Text(
            label,
            style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w700),
          ),
          SizedBox(height: 2.h),
          Text(
            sub,
            style: TextStyle(fontSize: 11.5.sp, color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}