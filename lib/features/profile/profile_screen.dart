import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_loading.dart';
import '../../core/widgets/shared_widgets.dart';
import '../../data/models/models.dart';
import '../../providers/auth_provider.dart';
import '../../providers/profile_provider.dart';
import '../../providers/sos_provider.dart';
import 'ai_insights_list_screen.dart';
import 'edit_health_profile_sheet.dart';
import 'edit_profile_screen.dart';
import 'emergency_contacts_screen.dart';
import 'nutrition_history_screen.dart';
import 'prescription_history_screen.dart';
import '../notifications/notifications_screen.dart';
import '../settings/alarm_sound_screen.dart';
import '../skin/skin_history_screen.dart';
import '../vitals/vitals_history_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<ProfileProvider>();

    if (prov.isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Profile')),
        body: const Center(
          child: AppSectionLoader(label: 'Loading your profile…'),
        ),
      );
    }

    final p = prov.profile;

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(20.w, 8.h, 20.w, 24.h),
        children: [
          MCard(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const EditProfileScreen()),
            ),
            child: Row(
              children: [
                InitialsAvatar(p.name, size: 56.r, imageUrl: p.imageUrl),
                SizedBox(width: 14.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p.name.isEmpty ? 'Complete your profile' : p.name,
                        style: GoogleFonts.sora(
                          fontSize: 16.sp,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: 3.h),
                      Text(
                        firebaseAuthEmail(context),
                        style: TextStyle(
                          fontSize: 12.5.sp,
                          color: AppColors.muted,
                        ),
                      ),
                      if (p.dob.isNotEmpty) ...[
                        SizedBox(height: 2.h),
                        Text(
                          p.dob,
                          style: TextStyle(
                            fontSize: 12.sp,
                            color: AppColors.muted,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.muted,
                  size: 24.sp,
                ),
              ],
            ),
          ),
          SizedBox(height: 20.h),
          Padding(
            padding: EdgeInsets.only(bottom: 10.h, top: 4.h),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Health profile',
                    style: Theme.of(
                      context,
                    ).textTheme.titleMedium?.copyWith(fontSize: 16.sp),
                  ),
                ),
                GestureDetector(
                  onTap: () => showEditHealthProfileSheet(context),
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: 10.w,
                      vertical: 7.h,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.soft,
                      borderRadius: BorderRadius.circular(999.r),
                      border: Border.all(
                        color: AppColors.primary.withValues(alpha: .24),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.edit_rounded,
                          size: 15.sp,
                          color: AppColors.primary,
                        ),
                        SizedBox(width: 6.w),
                        Text(
                          'Edit',
                          style: TextStyle(
                            fontSize: 12.5.sp,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          MCard(
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _Vital(label: 'Blood', value: p.bloodType),
                    _Vital(label: 'Height', value: p.heightLabel),
                    _Vital(label: 'Weight', value: '${p.weightLb} lb'),
                    _Vital(
                      label: 'Born',
                      value: p.dob.isEmpty ? '—' : p.dob.split(',').first,
                    ),
                  ],
                ),
                Divider(height: 24.h),
                _ChipRow(
                  label: 'Allergies',
                  values: p.allergies,
                  background: AppColors.dangerSoft,
                  foreground: AppColors.danger,
                ),
                SizedBox(height: 10.h),
                _ChipRow(
                  label: 'Conditions',
                  values: p.conditions,
                  background: AppColors.warningSoft,
                  foreground: AppColors.warning,
                ),
                SizedBox(height: 10.h),
                _ChipRow(
                  label: 'Medications',
                  values: p.medications,
                  background: AppColors.soft,
                  foreground: AppColors.onSoft,
                ),
              ],
            ),
          ),
          SizedBox(height: 20.h),
          Padding(
            padding: EdgeInsets.only(bottom: 10.h, top: 4.h),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'AI Insights',
                    style: Theme.of(
                      context,
                    ).textTheme.titleMedium?.copyWith(fontSize: 16.sp),
                  ),
                ),
                if (prov.aiInsights.isNotEmpty)
                  GestureDetector(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const AiInsightsListScreen(),
                      ),
                    ),
                    child: Text(
                      'See all',
                      style: TextStyle(
                        fontSize: 13.sp,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          _AiInsightsSummaryCard(insights: prov.aiInsights),
          SizedBox(height: 20.h),
          const SectionHeader('Emergency'),
          MCard(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const EmergencyContactsScreen(),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 42.r,
                  height: 42.r,
                  decoration: BoxDecoration(
                    color: AppColors.dangerSoft,
                    borderRadius: BorderRadius.circular(13.r),
                  ),
                  child: Icon(
                    Icons.contact_emergency_rounded,
                    color: AppColors.danger,
                    size: 22.sp,
                  ),
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Emergency contacts',
                        style: TextStyle(
                          fontSize: 14.5.sp,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${prov.contacts.length} saved · alerted during SOS',
                        style: TextStyle(
                          fontSize: 12.sp,
                          color: AppColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.muted,
                  size: 24.sp,
                ),
              ],
            ),
          ),
          SizedBox(height: 10.h),
          // SOS Accessibility Toggle Card
          Consumer<SosProvider>(
            builder: (context, sos, _) => MCard(
              child: Row(
                children: [
                  Container(
                    width: 42.r,
                    height: 42.r,
                    decoration: BoxDecoration(
                      color: AppColors.danger.withValues(alpha: .1),
                      borderRadius: BorderRadius.circular(13.r),
                    ),
                    child: Icon(
                      Icons.emergency_rounded,
                      color: AppColors.danger,
                      size: 22.sp,
                    ),
                  ),
                  SizedBox(width: 12.w),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'SOS Assist Button',
                          style: TextStyle(
                            fontSize: 14.5.sp,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          'Floating button for quick SOS',
                          style: TextStyle(
                            fontSize: 12.sp,
                            color: AppColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch.adaptive(
                    value: sos.showAccessibilityButton,
                    activeThumbColor: AppColors.danger,
                    onChanged: (v) => sos.toggleAccessibilityButton(v),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(height: 20.h),
          const SectionHeader('Settings'),
          MCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _SettingTile(
                  icon: Icons.notifications_outlined,
                  label: 'Notifications',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const NotificationsScreen(),
                      ),
                    );
                  },
                ),
                Divider(height: 1.h, indent: 56.w),
                _SettingTile(
                  icon: Icons.alarm_rounded,
                  label: 'Alarm sound',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AlarmSoundScreen()),
                  ),
                ),
                Divider(height: 1.h, indent: 56.w),
                _SettingTile(
                  icon: Icons.restaurant_rounded,
                  label: 'Nutrition',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const NutritionHistoryScreen(),
                    ),
                  ),
                ),
                Divider(height: 1.h, indent: 56.w),
                _SettingTile(
                  icon: Icons.receipt_long_rounded,
                  label: 'Prescription history',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const PrescriptionHistoryScreen(),
                    ),
                  ),
                ),
                Divider(height: 1.h, indent: 56.w),
                _SettingTile(
                  icon: Icons.face_retouching_natural_rounded,
                  label: 'Skin check history',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const SkinHistoryScreen(),
                    ),
                  ),
                ),
                Divider(height: 1.h, indent: 56.w),
                _SettingTile(
                  icon: Icons.favorite_border_rounded,
                  label: 'Heart rate history',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const VitalsHistoryScreen(),
                    ),
                  ),
                ),
                Divider(height: 1.h, indent: 56.w),
                _SettingTile(
                  icon: Icons.lock_outline_rounded,
                  label: 'Privacy & data',
                  onTap: () => showToast(context, 'Privacy settings'),
                ),
                Divider(height: 1.h, indent: 56.w),
                _SettingTile(
                  icon: Icons.help_outline_rounded,
                  label: 'Help & support',
                  onTap: () => showToast(context, 'Support center'),
                ),
                Divider(height: 1.h, indent: 56.w),
                _SettingTile(
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
                    await context.read<AuthProvider>().logout();
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Small helper so the profile card shows the signed-in email without
/// importing FirebaseAuth directly into every widget below.
String firebaseAuthEmail(BuildContext context) {
  return context.read<AuthProvider>().currentEmail;
}

/// Shows the short personalized facts MedAI has picked up while chatting
/// (symptoms, ongoing concerns, preferences) — a live view into what's
/// making the AI's answers personalized, instead of that context living
/// invisibly inside old chat threads.
class _AiInsightsSummaryCard extends StatelessWidget {
  const _AiInsightsSummaryCard({required this.insights});

  final List<AiInsight> insights;

  @override
  Widget build(BuildContext context) {
    if (insights.isEmpty) {
      return MCard(
        color: AppColors.aiSoft,
        border: Border.all(color: AppColors.ai.withValues(alpha: .3)),
        child: Row(
          children: [
            Icon(Icons.auto_awesome_rounded, color: AppColors.ai, size: 22.sp),
            SizedBox(width: 12.w),
            Expanded(
              child: Text(
                'Nothing learned yet — context like symptoms will show up here as you chat.',
                style: TextStyle(
                  fontSize: 12.5.sp,
                  height: 1.4,
                  color: AppColors.inkSoft,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final latest = insights.first;

    return MCard(
      onTap: () => Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const AiInsightsListScreen())),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.auto_awesome_rounded,
                color: AppColors.ai,
                size: 16.sp,
              ),
              SizedBox(width: 8.w),
              Expanded(
                child: Text(
                  'Latest from MedAI',
                  style: TextStyle(
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ai,
                  ),
                ),
              ),
              Text(
                '${insights.length} total',
                style: TextStyle(fontSize: 11.sp, color: AppColors.muted),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 16.sp,
                color: AppColors.muted,
              ),
            ],
          ),
          SizedBox(height: 12.h),
          Text(
            latest.text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13.5.sp,
              fontWeight: FontWeight.w600,
              color: AppColors.ink,
            ),
          ),
        ],
      ),
    );
  }
}

class _Vital extends StatelessWidget {
  const _Vital({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: GoogleFonts.sora(
            fontSize: 16.sp,
            fontWeight: FontWeight.w700,
            color: AppColors.primary,
          ),
        ),
        SizedBox(height: 2.h),
        Text(
          label,
          style: TextStyle(fontSize: 11.sp, color: AppColors.muted),
        ),
      ],
    );
  }
}

class _ChipRow extends StatelessWidget {
  const _ChipRow({
    required this.label,
    required this.values,
    required this.background,
    required this.foreground,
  });

  final String label;
  final List<String> values;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 92.w,
          child: Padding(
            padding: EdgeInsets.only(top: 4.h),
            child: Text(
              label,
              style: TextStyle(fontSize: 12.5.sp, color: AppColors.muted),
            ),
          ),
        ),
        Expanded(
          child: values.isEmpty
              ? Text(
            'Not set yet',
            style: TextStyle(fontSize: 12.5.sp, color: AppColors.muted),
          )
              : Wrap(
            spacing: 6.w,
            runSpacing: 6.h,
            children: [
              for (final v in values)
                MChip(v, background: background, foreground: foreground),
            ],
          ),
        ),
      ],
    );
  }
}

class _SettingTile extends StatelessWidget {
  const _SettingTile({
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
      child: ListTile(
        onTap: onTap,
        leading: Icon(
          icon,
          color: color == AppColors.ink ? AppColors.inkSoft : color,
          size: 22.sp,
        ),
        title: Text(
          label,
          style: TextStyle(
            fontSize: 14.sp,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
        trailing: Icon(
          Icons.chevron_right_rounded,
          color: AppColors.muted,
          size: 20.sp,
        ),
      ),
    );
  }
}