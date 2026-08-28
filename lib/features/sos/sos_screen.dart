import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/services/emergency_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/shared_widgets.dart';
import '../../data/models/models.dart';
import '../../providers/location_provider.dart';
import '../../providers/profile_provider.dart';
import '../../providers/sos_provider.dart';
import '../profile/emergency_contacts_screen.dart';

/// Resolves the police/ambulance/fire dial numbers using the user's real,
/// detected country (from [LocationProvider.countryCode]) instead of an
/// unset default.
EmergencyNumbers _resolveEmergencyNumbers(BuildContext context) {
  final countryCode = context.read<LocationProvider>().countryCode;
  return EmergencyNumberService.instance
      .emergencyNumbers(countryCode: countryCode);
}

void _callNumber(String number) {
  launchUrl(Uri.parse('tel:$number'));
}

/// Row of three compact call buttons — Police / Ambulance / Fire — each
/// dialling its own service-specific number for the user's country.
class _EmergencyServiceButtons extends StatelessWidget {
  const _EmergencyServiceButtons();

  @override
  Widget build(BuildContext context) {
    final numbers = _resolveEmergencyNumbers(context);
    return IntrinsicHeight(
      child: Row(
        children: [
          Expanded(
            child: PrimaryButton(
              label: 'POLICE',
              subLabel: numbers.police,
              icon: Icons.local_police_rounded,
              color: const Color(0xFF2A6DF4),
              onPressed: () => _callNumber(numbers.police),
            ),
          ),
          SizedBox(width: 8.w),
          Expanded(
            child: PrimaryButton(
              label: 'AMBULANCE',
              subLabel: numbers.ambulance,
              icon: Icons.local_hospital_rounded,
              color: AppColors.danger,
              onPressed: () => _callNumber(numbers.ambulance),
            ),
          ),
          SizedBox(width: 8.w),
          Expanded(
            child: PrimaryButton(
              label: 'FIRE',
              subLabel: numbers.fire,
              icon: Icons.local_fire_department_rounded,
              color: const Color(0xFFE07C1F),
              onPressed: () => _callNumber(numbers.fire),
            ),
          ),
        ],
      ),
    );
  }
}

class SosScreen extends StatelessWidget {
  const SosScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final sos = context.watch<SosProvider>();
    if (sos.phase == SosPhase.countdown) return const _CountdownView();
    if (sos.phase == SosPhase.cancelling) return const _SosCancellingView();
    if (sos.phase == SosPhase.failed) return const _SosErrorView();
    if (sos.phase == SosPhase.cancelled || sos.phase == SosPhase.resolved) {
      return const _SosEndedView();
    }
    return const _ActiveSosView();
  }
}

class _SosErrorView extends StatelessWidget {
  const _SosErrorView();

  @override
  Widget build(BuildContext context) {
    final sos = context.watch<SosProvider>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Emergency SOS'),
        backgroundColor: AppColors.dangerSoft,
      ),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(24.r),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.location_off_rounded, size: 64.sp, color: AppColors.danger),
              SizedBox(height: 16.h),
              Text(
                'Unable to determine current location',
                style: TextStyle(fontSize: 22.sp, fontWeight: FontWeight.w700),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 12.h),
              Text(
                sos.errorMessage ?? 'Location access is required to create a real SOS session.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14.sp, color: AppColors.muted, height: 1.5),
              ),
              SizedBox(height: 24.h),
              const _EmergencyServiceButtons(),
            ],
          ),
        ),
      ),
    );
  }
}

class _SosCancellingView extends StatelessWidget {
  const _SosCancellingView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Emergency SOS'), automaticallyImplyLeading: false),
      body: const SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: AppColors.danger),
              SizedBox(height: 16),
              Text('Cancelling SOS…', style: TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }
}

class _SosEndedView extends StatelessWidget {
  const _SosEndedView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Emergency SOS')),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(24.r),
            child: Text(
              'SOS session closed.',
              style: TextStyle(fontSize: 20.sp, fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}

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
          onPressed: () async {
            await context.read<SosProvider>().cancel();
            if (context.mounted) Navigator.of(context).pop();
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
                  'Your emergency contacts will be alerted\nwith your live location',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 14.sp,
                      height: 1.5,
                      color: Colors.white.withValues(alpha: .75))),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () async {
                    await context.read<SosProvider>().cancel();
                    if (context.mounted) Navigator.of(context).pop();
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
        automaticallyImplyLeading: false,
        actions: [
          TextButton(
            onPressed: () async {
              await context.read<SosProvider>().resolve();
              if (context.mounted) {
                Navigator.of(context).popUntil((r) => r.isFirst);
              }
            },
            child: const Text('RESOLVE', style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      backgroundColor: const Color(0xFFFFF7F6),
      body: ListView(
        padding: EdgeInsets.fromLTRB(20.w, 10.h, 20.w, 24.h),
        children: [
          // Live Map Tracker
          if (sos.userLocation != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(20.r),
              child: Container(
                height: 200.h,
                margin: EdgeInsets.only(bottom: 16.h),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.danger.withValues(alpha: 0.1)),
                ),
                child: FlutterMap(
                  options: MapOptions(
                    initialCenter: sos.userLocation!,
                    initialZoom: 14.0,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.medisense.medisense_app',
                    ),
                    if (sos.currentRoutePoints.isNotEmpty)
                      PolylineLayer(polylines: [
                        Polyline(
                          points: sos.currentRoutePoints,
                          strokeWidth: 4.w,
                          color: AppColors.danger,
                        ),
                      ]),
                    MarkerLayer(markers: [
                      Marker(
                        point: sos.userLocation!,
                        width: 30.r, height: 30.r,
                        child: Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF2A6DF4),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 3.w),
                            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10)],
                          ),
                        ),
                      ),
                      if (sos.selectedHospital != null)
                        Marker(
                          point: sos.selectedHospital!.position,
                          width: 40.r, height: 40.r,
                          child: Container(
                            decoration: BoxDecoration(
                              color: AppColors.danger,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2.w),
                            ),
                            child: const Icon(Icons.local_hospital_rounded, color: Colors.white, size: 20),
                          ),
                        ),
                    ]),
                  ],
                ),
              ),
            ),

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
                Icon(sos.userLocation != null ? Icons.gps_fixed_rounded : Icons.gps_off_rounded, color: Colors.white, size: 24.sp),
                SizedBox(width: 12.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        sos.userLocation != null ? 'SOS ACTIVE · Tracking on' : 'SOS ACTIVE · Locating...',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 15.sp),
                      ),
                      if (sos.selectedHospital != null && sos.realEtaMinutes > 0)
                        Text(
                          'ETA to ER: ${sos.realEtaMinutes.toStringAsFixed(0)} min',
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 12.sp, fontWeight: FontWeight.w600),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 14.h),

          const _EmergencyServiceButtons(),
          SizedBox(height: 10.h),
          PrimaryButton(
            label: 'OPEN MAPS',
            icon: Icons.directions_rounded,
            color: AppColors.ink,
            onPressed: () {
              if (sos.selectedHospital != null) {
                _openDirections(sos.selectedHospital!);
              }
            },
          ),

          SizedBox(height: 20.h),
          Text('NEAREST HOSPITALS',
              style: TextStyle(
                  fontSize: 12.sp,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                  color: AppColors.muted)),
          SizedBox(height: 10.h),
          if (sos.isLoadingHospitals)
            const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()))
          else if (sos.nearbyHospitals.isEmpty)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text('No hospitals found nearby.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted)),
            )
          else
            for (final h in sos.nearbyHospitals)
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
                                '${h.distanceMiles.toStringAsFixed(1)} mi · ${h.openLabel}',
                                style: TextStyle(
                                    fontSize: 12.sp, color: AppColors.muted)),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.directions_rounded, color: AppColors.primary),
                        onPressed: () => _openDirections(h),
                      ),
                    ],
                  ),
                ),
              ),

          SizedBox(height: 14.h),
          MCard(
            padding:
            EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
            child: Row(
              children: [
                Icon(
                  sos.contactsNotified ? Icons.check_circle_rounded : Icons.sync_rounded,
                  color: sos.contactsNotified ? AppColors.success : AppColors.muted,
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        sos.contactNotificationStatus == 'failed'
                            ? 'Contact alerts failed'
                            : sos.contactNotificationStatus == 'pending'
                            ? 'Contact alerts pending'
                            : 'Contacts notified',
                        style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w700),
                      ),
                      Text(
                        contactNames.isEmpty ? 'No emergency contacts saved' : contactNames,
                        style: TextStyle(fontSize: 12.sp, color: AppColors.muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          SizedBox(height: 14.h),
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
                    Text('Medical ID',
                        style: GoogleFonts.sora(
                            fontSize: 13.5.sp, fontWeight: FontWeight.w700)),
                  ],
                ),
                SizedBox(height: 8.h),
                Text(
                  '${p.bloodType} · allergies: ${p.allergies.isEmpty ? "None" : p.allergies.join(", ")} · '
                      '${p.conditions.isEmpty ? "No conditions" : p.conditions.join(", ")}',
                  style: TextStyle(
                      fontSize: 12.5.sp,
                      height: 1.5,
                      color: AppColors.inkSoft),
                ),
              ],
            ),
          ),
          SizedBox(height: 20.h),
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
        ],
      ),
    );
  }

  Future<void> _openDirections(Facility f) async {
    final dest = '${f.position.latitude},${f.position.longitude}';
    final uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$dest'
          '&travelmode=driving',
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}