import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/services/emergency_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_loading.dart';
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
  return EmergencyNumberService.instance.emergencyNumbers(
    countryCode: countryCode,
  );
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
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _ServiceTile(
              icon: Icons.local_police_rounded,
              label: 'Police',
              number: numbers.police,
              color: AppColors.primaryDark,
              background: AppColors.soft,
              onTap: () => _callNumber(numbers.police),
            ),
          ),
          SizedBox(width: 10.w),
          Expanded(
            child: _ServiceTile(
              icon: Icons.local_hospital_rounded,
              label: 'Medical',
              number: numbers.ambulance,
              color: AppColors.danger,
              background: AppColors.dangerSoft,
              onTap: () => _callNumber(numbers.ambulance),
            ),
          ),
          SizedBox(width: 10.w),
          Expanded(
            child: _ServiceTile(
              icon: Icons.local_fire_department_rounded,
              label: 'Fire',
              number: numbers.fire,
              color: AppColors.warning,
              background: AppColors.warningSoft,
              onTap: () => _callNumber(numbers.fire),
            ),
          ),
        ],
      ),
    );
  }
}

/// Soft-card emergency service tile — matches the app's card language
/// (white surface, tinted icon badge) instead of a solid saturated block,
/// so Police/Medical/Fire sit visually inside the app rather than looking
/// like a separate, mismatched screen.
class _LivePulseDot extends StatefulWidget {
  const _LivePulseDot({this.color = Colors.white, this.size = 7});

  final Color color;
  final double size;

  @override
  State<_LivePulseDot> createState() => _LivePulseDotState();
}

class _LivePulseDotState extends State<_LivePulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size.sp * 2.4,
      height: widget.size.sp * 2.4,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final t = _controller.value;
          return Stack(
            alignment: Alignment.center,
            children: [
              Opacity(
                opacity: (1 - t).clamp(0.0, 1.0),
                child: Container(
                  width: widget.size.sp * 2.4 * (0.4 + t * 1.6),
                  height: widget.size.sp * 2.4 * (0.4 + t * 1.6),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.color.withValues(alpha: .5),
                  ),
                ),
              ),
              Container(
                width: widget.size.sp,
                height: widget.size.sp,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.color,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ServiceTile extends StatelessWidget {
  const _ServiceTile({
    required this.icon,
    required this.label,
    required this.number,
    required this.color,
    required this.background,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String number;
  final Color color;
  final Color background;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(18.r),
      child: InkWell(
        borderRadius: BorderRadius.circular(18.r),
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(vertical: 16.h, horizontal: 6.w),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18.r),
            border: Border.all(color: AppColors.line, width: 1.w),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: .10),
                blurRadius: 14.r,
                offset: Offset(0, 6.h),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 42.r,
                height: 42.r,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [background, background.withValues(alpha: .55)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: .18),
                      blurRadius: 8.r,
                      offset: Offset(0, 3.h),
                    ),
                  ],
                ),
                child: Icon(icon, color: color, size: 20.sp),
              ),
              SizedBox(height: 9.h),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5.sp,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                  letterSpacing: .1,
                ),
              ),
              SizedBox(height: 1.h),
              Text(
                number,
                style: TextStyle(
                  fontSize: 11.sp,
                  fontWeight: FontWeight.w600,
                  color: AppColors.muted,
                ),
              ),
            ],
          ),
        ),
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
              Icon(
                Icons.location_off_rounded,
                size: 64.sp,
                color: AppColors.danger,
              ),
              SizedBox(height: 16.h),
              Text(
                'Unable to determine current location',
                style: TextStyle(fontSize: 22.sp, fontWeight: FontWeight.w700),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 12.h),
              Text(
                sos.errorMessage ??
                    'Location access is required to create a real SOS session.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14.sp,
                  color: AppColors.muted,
                  height: 1.5,
                ),
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
      appBar: AppBar(
        title: const Text('Emergency SOS'),
        automaticallyImplyLeading: false,
      ),
      body: const SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppSpinner(size: 40, color: AppColors.danger),
              SizedBox(height: 16),
              Text(
                'Cancelling SOS…',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
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
      backgroundColor: AppColors.dangerDark,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: const Text('Emergency SOS'),
        titleTextStyle: GoogleFonts.sora(
          fontSize: 18.sp,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
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
              Text(
                'Sending alert in',
                style: TextStyle(
                  fontSize: 16.sp,
                  color: Colors.white.withValues(alpha: .8),
                ),
              ),
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
                      spreadRadius: 8.r,
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: Text(
                  '${sos.countdown}',
                  style: GoogleFonts.sora(
                    fontSize: 72.sp,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
              SizedBox(height: 26.h),
              Text(
                'Your emergency contacts will be alerted\nwith your live location',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14.sp,
                  height: 1.5,
                  color: Colors.white.withValues(alpha: .75),
                ),
              ),
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
                      borderRadius: BorderRadius.circular(14.r),
                    ),
                  ),
                  child: Text(
                    "I'M SAFE — CANCEL",
                    style: TextStyle(
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
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

class _ActiveSosView extends StatefulWidget {
  const _ActiveSosView();

  @override
  State<_ActiveSosView> createState() => _ActiveSosViewState();
}

class _ActiveSosViewState extends State<_ActiveSosView> {
  final MapController _mapController = MapController();

  void _recenter(LatLng? location) {
    if (location == null) return;
    try {
      _mapController.move(location, 15.0);
    } catch (_) {
      // Map not laid out yet — ignore, matches prior silent-no-op behavior.
    }
  }

  @override
  Widget build(BuildContext context) {
    final sos = context.watch<SosProvider>();
    final profile = context.watch<ProfileProvider>();
    final p = profile.profile;
    final contactNames = profile.contacts
        .map((c) => c.name.split(' ').first)
        .join(' · ');

    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Emergency'),
            SizedBox(width: 8.w),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
              decoration: BoxDecoration(
                color: AppColors.dangerSoft,
                borderRadius: BorderRadius.circular(99.r),
                border: Border.all(
                  color: AppColors.danger.withValues(alpha: .25),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _LivePulseDot(color: AppColors.danger, size: 6),
                  SizedBox(width: 5.w),
                  Text(
                    'LIVE',
                    style: TextStyle(
                      fontSize: 10.sp,
                      fontWeight: FontWeight.w800,
                      letterSpacing: .6,
                      color: AppColors.danger,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        backgroundColor: AppColors.paper,
        foregroundColor: AppColors.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: false,
        actions: [
          TextButton.icon(
            onPressed: () async {
              await context.read<SosProvider>().resolve();
              if (context.mounted) {
                Navigator.of(context).popUntil((r) => r.isFirst);
              }
            },
            icon: Icon(
              Icons.call_end_rounded,
              size: 16.sp,
              color: AppColors.danger,
            ),
            label: Text(
              'RESOLVE',
              style: TextStyle(
                color: AppColors.danger,
                fontWeight: FontWeight.bold,
                fontSize: 13.sp,
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(20.w, 10.h, 20.w, 24.h),
        children: [
          Text(
            "We're here to help. Stay safe!",
            style: TextStyle(
              fontSize: 13.sp,
              color: AppColors.muted,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: 14.h),

          // Live Map Tracker
          if (sos.userLocation != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(20.r),
              child: Container(
                height: 200.h,
                margin: EdgeInsets.only(bottom: 16.h),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.line),
                ),
                child: Stack(
                  children: [
                    FlutterMap(
                      mapController: _mapController,
                      options: MapOptions(
                        initialCenter: sos.userLocation!,
                        initialZoom: 14.0,
                      ),
                      children: [
                        TileLayer(
                          urlTemplate:
                              'https://basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png',
                          userAgentPackageName: 'com.medisense.medisense_app',
                        ),
                        if (sos.currentRoutePoints.isNotEmpty)
                          PolylineLayer(
                            polylines: [
                              Polyline(
                                points: sos.currentRoutePoints,
                                strokeWidth: 4.w,
                                color: AppColors.danger,
                              ),
                            ],
                          ),
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: sos.userLocation!,
                              width: 30.r,
                              height: 30.r,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: AppColors.primary,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 3.w,
                                  ),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Colors.black26,
                                      blurRadius: 10,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            if (sos.selectedHospital != null)
                              Marker(
                                point: sos.selectedHospital!.position,
                                width: 40.r,
                                height: 40.r,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: AppColors.danger,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 2.w,
                                    ),
                                  ),
                                  child: const Icon(
                                    Icons.local_hospital_rounded,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                    Positioned(
                      right: 10.w,
                      bottom: 10.h,
                      child: Material(
                        color: Colors.white,
                        shape: const CircleBorder(),
                        elevation: 3,
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () => _recenter(sos.userLocation),
                          child: Padding(
                            padding: EdgeInsets.all(9.r),
                            child: Icon(
                              Icons.my_location_rounded,
                              size: 19.sp,
                              color: AppColors.ink,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          ClipRRect(
            borderRadius: BorderRadius.circular(20.r),
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 18.w, vertical: 16.h),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: AppColors.dangerGradient,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20.r),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.danger.withValues(alpha: .32),
                    blurRadius: 20.r,
                    offset: Offset(0, 10.h),
                  ),
                ],
              ),
              child: Stack(
                children: [
                  Positioned(
                    right: -20.r,
                    top: -30.r,
                    child: Container(
                      width: 110.r,
                      height: 110.r,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: .06),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 40.r,
                    bottom: -36.r,
                    child: Container(
                      width: 70.r,
                      height: 70.r,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: .05),
                      ),
                    ),
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        width: 46.r,
                        height: 46.r,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: .18),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withValues(alpha: .25),
                            width: 1.2.w,
                          ),
                        ),
                        child: Icon(
                          sos.userLocation != null
                              ? Icons.crisis_alert_rounded
                              : Icons.gps_off_rounded,
                          color: Colors.white,
                          size: 23.sp,
                        ),
                      ),
                      SizedBox(width: 14.w),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                _LivePulseDot(color: Colors.white, size: 6),
                                SizedBox(width: 6.w),
                                Text(
                                  'SOS ACTIVE',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: .9),
                                    fontWeight: FontWeight.w800,
                                    fontSize: 11.sp,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 4.h),
                            Text(
                              sos.userLocation != null
                                  ? 'Tracking on'
                                  : 'Locating…',
                              style: GoogleFonts.sora(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 17.sp,
                              ),
                            ),
                            if (sos.selectedHospital != null &&
                                sos.realEtaMinutes > 0) ...[
                              SizedBox(height: 3.h),
                              Row(
                                children: [
                                  Icon(
                                    Icons.timer_outlined,
                                    size: 13.sp,
                                    color: Colors.white.withValues(alpha: .85),
                                  ),
                                  SizedBox(width: 4.w),
                                  Text(
                                    'ETA to ER: ${sos.realEtaMinutes.toStringAsFixed(0)} min',
                                    style: TextStyle(
                                      color: Colors.white.withValues(
                                        alpha: 0.9,
                                      ),
                                      fontSize: 12.sp,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      Container(
                        padding: EdgeInsets.all(6.r),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: .16),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.chevron_right_rounded,
                          color: Colors.white,
                          size: 18.sp,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
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
          Row(
            children: [
              Icon(
                Icons.local_hospital_rounded,
                size: 15.sp,
                color: AppColors.primaryDark,
              ),
              SizedBox(width: 6.w),
              Text(
                'NEAREST HOSPITALS',
                style: TextStyle(
                  fontSize: 12.sp,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                  color: AppColors.inkSoft,
                ),
              ),
              if (sos.nearbyHospitals.isNotEmpty) ...[
                SizedBox(width: 8.w),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 7.w, vertical: 2.h),
                  decoration: BoxDecoration(
                    color: AppColors.soft,
                    borderRadius: BorderRadius.circular(99.r),
                  ),
                  child: Text(
                    '${sos.nearbyHospitals.length}',
                    style: TextStyle(
                      fontSize: 10.5.sp,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primaryDark,
                    ),
                  ),
                ),
              ],
            ],
          ),
          SizedBox(height: 10.h),
          if (sos.isLoadingHospitals)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: AppSectionLoader(
                  label: 'Finding nearby hospitals…',
                  color: AppColors.danger,
                ),
              ),
            )
          else if (sos.nearbyHospitals.isEmpty)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                'No hospitals found nearby.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.muted),
              ),
            )
          else
            for (final h in sos.nearbyHospitals)
              Padding(
                padding: EdgeInsets.only(bottom: 10.h),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18.r),
                    boxShadow: sos.selectedHospital == h
                        ? [
                            BoxShadow(
                              color: AppColors.danger.withValues(alpha: .16),
                              blurRadius: 16.r,
                              offset: Offset(0, 6.h),
                            ),
                          ]
                        : [],
                  ),
                  child: MCard(
                    onTap: () => context.read<SosProvider>().selectHospital(h),
                    padding: EdgeInsets.symmetric(
                      horizontal: 14.w,
                      vertical: 13.h,
                    ),
                    border: sos.selectedHospital == h
                        ? Border.all(color: AppColors.danger, width: 1.6.w)
                        : null,
                    child: Row(
                      children: [
                        Icon(
                          sos.selectedHospital == h
                              ? Icons.check_circle_rounded
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
                              Text(
                                h.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 14.5.sp,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.ink,
                                ),
                              ),
                              SizedBox(height: 3.h),
                              Row(
                                children: [
                                  Container(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 6.w,
                                      vertical: 1.h,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppColors.soft,
                                      borderRadius: BorderRadius.circular(99.r),
                                    ),
                                    child: Text(
                                      '${h.distanceMiles.toStringAsFixed(1)} mi',
                                      style: TextStyle(
                                        fontSize: 10.5.sp,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.primaryDark,
                                      ),
                                    ),
                                  ),
                                  SizedBox(width: 6.w),
                                  Expanded(
                                    child: Text(
                                      h.openLabel,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 12.sp,
                                        color: AppColors.muted,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        Material(
                          color: AppColors.soft,
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: () => _openDirections(h),
                            child: Padding(
                              padding: EdgeInsets.all(9.r),
                              child: Icon(
                                Icons.directions_rounded,
                                color: AppColors.primaryDark,
                                size: 19.sp,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

          SizedBox(height: 14.h),
          MCard(
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
            child: Row(
              children: [
                Container(
                  width: 38.r,
                  height: 38.r,
                  decoration: BoxDecoration(
                    color: sos.contactsNotified
                        ? AppColors.successSoft
                        : AppColors.paper,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    sos.contactsNotified
                        ? Icons.check_circle_rounded
                        : Icons.sync_rounded,
                    color: sos.contactsNotified
                        ? AppColors.success
                        : AppColors.muted,
                    size: 19.sp,
                  ),
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
                        style: TextStyle(
                          fontSize: 14.sp,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink,
                        ),
                      ),
                      Text(
                        contactNames.isEmpty
                            ? 'No emergency contacts saved'
                            : contactNames,
                        style: TextStyle(
                          fontSize: 12.sp,
                          color: AppColors.muted,
                        ),
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
                    Icon(
                      Icons.medical_information_rounded,
                      color: AppColors.danger,
                      size: 20.sp,
                    ),
                    SizedBox(width: 8.w),
                    Text(
                      'Medical ID',
                      style: GoogleFonts.sora(
                        fontSize: 13.5.sp,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 8.h),
                Text(
                  '${p.bloodType} · allergies: ${p.allergies.isEmpty ? "None" : p.allergies.join(", ")} · '
                  '${p.conditions.isEmpty ? "No conditions" : p.conditions.join(", ")}',
                  style: TextStyle(
                    fontSize: 12.5.sp,
                    height: 1.5,
                    color: AppColors.inkSoft,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 20.h),
          Center(
            child: TextButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const EmergencyContactsScreen(),
                ),
              ),
              icon: Icon(
                Icons.person_add_alt_rounded,
                size: 18.sp,
                color: AppColors.muted,
              ),
              label: Text(
                'Manage emergency contacts',
                style: TextStyle(
                  fontSize: 14.sp,
                  color: AppColors.muted,
                  fontWeight: FontWeight.w600,
                ),
              ),
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
