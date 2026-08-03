import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/shared_widgets.dart';
import '../../data/mock/mock_data.dart';
import '../../providers/profile_provider.dart';
import '../../providers/sos_provider.dart';
import '../profile/emergency_contacts_screen.dart';
import 'emergency_ride_screen.dart';

/// Emergency SOS — 5-second cancel countdown, then the Khidma-style
/// emergency screen: call buttons that work without data, nearest ER
/// selection, and a direct emergency-ride booking. ≤3 taps to a ride.
class SosScreen extends StatelessWidget {
  const SosScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final sos = context.watch<SosProvider>();
    if (sos.phase == SosPhase.countdown) return const _CountdownView();
    return const _ActiveSosView();
  }
}

// ── Phase 1 · dark countdown ────────────────────────────────────────────

class _CountdownView extends StatelessWidget {
  const _CountdownView();

  @override
  Widget build(BuildContext context) {
    final sos = context.watch<SosProvider>();
    return Scaffold(
      backgroundColor: const Color(0xFF2A0F0D),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: const Text('Emergency SOS'),
        titleTextStyle: GoogleFonts.sora(
            fontSize: 18.sp, fontWeight: FontWeight.w700, color: Colors.white),
        leading: IconButton(
          icon: Icon(Icons.close_rounded, size: 24.sp),
          onPressed: () {
            context.read<SosProvider>().cancel();
            Navigator.of(context).pop();
          },
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(24.r),
          child: Column(
            children: [
              const Spacer(),
              Text('Sending alert in',
                  style: TextStyle(
                      fontSize: 16.sp,
                      color: Colors.white.withValues(alpha: .8))),
              SizedBox(height: 18.h),
              Container(
                width: 168.r,
                height: 168.r,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.danger,
                  boxShadow: [
                    BoxShadow(
                        color: AppColors.danger.withValues(alpha: .55),
                        blurRadius: 60.r,
                        spreadRadius: 8.r),
                  ],
                ),
                alignment: Alignment.center,
                child: Text('${sos.countdown}',
                    style: GoogleFonts.sora(
                        fontSize: 72.sp,
                        fontWeight: FontWeight.w700,
                        color: Colors.white)),
              ),
              SizedBox(height: 26.h),
              Text(
                  '911 + your emergency contacts will be alerted\nwith your live location',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 14.sp,
                      height: 1.5,
                      color: Colors.white.withValues(alpha: .75))),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () {
                    context.read<SosProvider>().cancel();
                    Navigator.of(context).pop();
                  },
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: Colors.white, width: 1.4.w),
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(vertical: 16.h),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14.r)),
                  ),
                  child: Text("I'M SAFE — CANCEL",
                      style: TextStyle(
                          fontSize: 14.sp,
                          fontWeight: FontWeight.w700, letterSpacing: 1)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Phase 2 · active SOS (old Khidma layout) ────────────────────────────

class _ActiveSosView extends StatelessWidget {
  const _ActiveSosView();

  @override
  Widget build(BuildContext context) {
    final sos = context.watch<SosProvider>();
    final profile = context.watch<ProfileProvider>();
    final p = profile.profile;
    final contactNames =
        profile.contacts.map((c) => c.name.split(' ').first).join(' · ');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Emergency'),
        backgroundColor: AppColors.dangerSoft,
      ),
      backgroundColor: const Color(0xFFFFF7F6),
      body: ListView(
        padding: EdgeInsets.fromLTRB(20.w, 10.h, 20.w, 24.h),
        children: [
          Container(
            padding:
                EdgeInsets.symmetric(horizontal: 18.w, vertical: 15.h),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [AppColors.danger, Color(0xFFE0554B)]),
              borderRadius: BorderRadius.circular(16.r),
            ),
            child: Row(
              children: [
                Icon(Icons.gps_fixed_rounded, color: Colors.white, size: 24.sp),
                SizedBox(width: 12.w),
                Expanded(
                  child: Text('SOS ACTIVE · location locked ✔',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 15.sp,
                          letterSpacing: .3)),
                ),
              ],
            ),
          ),
          SizedBox(height: 14.h),
          // Native-dial buttons — always on top, work with zero data.
          PrimaryButton(
            label: 'CALL 911',
            icon: Icons.call_rounded,
            color: AppColors.ink,
            subLabel: 'works without data',
            onPressed: () => launchUrl(Uri.parse('tel:911')),
          ),
          SizedBox(height: 10.h),
          OutlinedButton(
            onPressed: () => launchUrl(Uri.parse('tel:18002221222')),
            style: OutlinedButton.styleFrom(
              padding: EdgeInsets.symmetric(vertical: 15.h),
              side: BorderSide(color: AppColors.ink, width: 1.3.w),
              foregroundColor: AppColors.ink,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14.r)),
            ),
            child: Text('Poison Control · 1-800-222-1222',
                style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w700)),
          ),
          SizedBox(height: 20.h),
          Text('NEAREST HOSPITALS · ER OPEN',
              style: TextStyle(
                  fontSize: 12.sp,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                  color: AppColors.muted)),
          SizedBox(height: 10.h),
          for (final h in MockData.hospitals)
            Padding(
              padding: EdgeInsets.only(bottom: 9.h),
              child: MCard(
                onTap: () => context.read<SosProvider>().selectHospital(h),
                padding: EdgeInsets.symmetric(
                    horizontal: 14.w, vertical: 12.h),
                border: sos.selectedHospital == h
                    ? Border.all(color: AppColors.danger, width: 1.5.w)
                    : null,
                child: Row(
                  children: [
                    Icon(
                      sos.selectedHospital == h
                          ? Icons.radio_button_checked_rounded
                          : Icons.radio_button_off_rounded,
                      color: sos.selectedHospital == h
                          ? AppColors.danger
                          : AppColors.line,
                      size: 24.sp,
                    ),
                    SizedBox(width: 12.w),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(h.name,
                              style: TextStyle(
                                  fontSize: 14.5.sp,
                                  fontWeight: FontWeight.w700)),
                          Text(
                              '${h.distanceMiles} mi · ETA ${h.etaMinutes} min',
                              style: TextStyle(
                                  fontSize: 12.sp, color: AppColors.muted)),
                        ],
                      ),
                    ),
                    Icon(Icons.navigation_rounded,
                        size: 18.sp, color: AppColors.muted),
                  ],
                ),
              ),
            ),
          SizedBox(height: 10.h),
          PrimaryButton(
            label: 'BOOK EMERGENCY RIDE',
            icon: Icons.emergency_share_rounded,
            color: AppColors.danger,
            subLabel:
                'to ${sos.selectedHospital.name} · fare settles after the trip',
            onPressed: () {
              context.read<SosProvider>().bookRide();
              Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const EmergencyRideScreen()));
            },
          ),
          SizedBox(height: 14.h),
          MCard(
            padding:
                EdgeInsets.symmetric(horizontal: 16.w, vertical: 6.h),
            child: Material(
              color: Colors.transparent,
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: sos.notifyContacts,
                activeThumbColor: AppColors.danger,
                onChanged: (v) =>
                    context.read<SosProvider>().toggleNotifyContacts(v),
                title: Text('Auto-text emergency contacts',
                    style: TextStyle(
                        fontSize: 14.sp, fontWeight: FontWeight.w600)),
                subtitle: Text(
                    contactNames.isEmpty
                        ? 'No contacts yet — add one below'
                        : '$contactNames — live tracking link',
                    style: TextStyle(
                        fontSize: 12.sp, color: AppColors.muted)),
              ),
            ),
          ),
          SizedBox(height: 10.h),
          // Medical ID — the part responders see.
          MCard(
            border: Border.all(color: AppColors.danger.withValues(alpha: .3)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.medical_information_rounded,
                        color: AppColors.danger, size: 20.sp),
                    SizedBox(width: 8.w),
                    Text('Medical ID — shared with responders',
                        style: GoogleFonts.sora(
                            fontSize: 13.5.sp, fontWeight: FontWeight.w700)),
                  ],
                ),
                SizedBox(height: 8.h),
                Text(
                  '${p.bloodType} · allergies: ${p.allergies.join(", ")} · '
                  '${p.conditions.join(", ")} · meds: ${p.medications.join(", ")}',
                  style: TextStyle(
                      fontSize: 12.5.sp,
                      height: 1.5,
                      color: AppColors.inkSoft),
                ),
              ],
            ),
          ),
          SizedBox(height: 10.h),
          Center(
            child: TextButton.icon(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const EmergencyContactsScreen())),
              icon: Icon(Icons.person_add_alt_rounded,
                  size: 18.sp, color: AppColors.muted),
              label: Text('Manage emergency contacts',
                  style: TextStyle(
                      fontSize: 14.sp,
                      color: AppColors.muted, fontWeight: FontWeight.w600)),
            ),
          ),
          Center(
            child: Text(
                'If no driver accepts within 90 seconds, a full-screen '
                '911 call prompt opens automatically.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.sp, color: AppColors.muted)),
          ),
        ],
      ),
    );
  }
}
