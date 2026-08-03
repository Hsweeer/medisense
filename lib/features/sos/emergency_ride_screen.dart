import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/shared_widgets.dart';
import '../../data/mock/mock_data.dart';
import '../../providers/profile_provider.dart';
import '../../providers/sos_provider.dart';

/// Emergency ride tracking — driver info, live trip stages, shared Medical
/// ID, and confirmation that contacts got the tracking link.
class EmergencyRideScreen extends StatelessWidget {
  const EmergencyRideScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final sos = context.watch<SosProvider>();
    final profile = context.watch<ProfileProvider>();
    final p = profile.profile;

    final bannerText = switch (sos.stage) {
      RideStage.assigned =>
        'DRIVER ON THE WAY · ETA ${sos.driverEtaMinutes} min',
      RideStage.pickedUp => 'PICKED UP · heading to the ER',
      RideStage.arrived => 'ARRIVED AT ER ✔',
      _ => 'FINDING NEAREST DRIVER…',
    };

    return Scaffold(
      appBar: AppBar(
        title: const Text('Emergency ride'),
        backgroundColor: AppColors.dangerSoft,
      ),
      backgroundColor: const Color(0xFFFFF7F6),
      body: ListView(
        padding: EdgeInsets.fromLTRB(20.w, 10.h, 20.w, 24.h),
        children: [
          Container(
            padding:
                EdgeInsets.symmetric(horizontal: 18.w, vertical: 14.h),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [AppColors.danger, Color(0xFFE0554B)]),
              borderRadius: BorderRadius.circular(16.r),
            ),
            child: Row(
              children: [
                Icon(Icons.emergency_share_rounded,
                    color: Colors.white, size: 24.sp),
                SizedBox(width: 12.w),
                Expanded(
                  child: Text(bannerText,
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 14.5.sp)),
                ),
              ],
            ),
          ),
          SizedBox(height: 14.h),
          // Live trip map: you → selected ER.
          ClipRRect(
            borderRadius: BorderRadius.circular(16.r),
            child: SizedBox(
              height: 170.h,
              child: FlutterMap(
                options: MapOptions(
                  initialCenter: MockData.userLocation,
                  initialZoom: 12.6,
                  interactionOptions: const InteractionOptions(
                      flags: InteractiveFlag.none),
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.medisense.medisense_app',
                  ),
                  PolylineLayer(polylines: [
                    Polyline(
                      points: [
                        MockData.userLocation,
                        sos.selectedHospital.position,
                      ],
                      strokeWidth: 4.w,
                      color: AppColors.danger,
                    ),
                  ]),
                  MarkerLayer(markers: [
                    Marker(
                      point: MockData.userLocation,
                      width: 22.r,
                      height: 22.r,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: const Color(0xFF2A6DF4),
                          shape: BoxShape.circle,
                          border:
                              Border.fromBorderSide(BorderSide(
                                  color: Colors.white, width: 3.w)),
                        ),
                      ),
                    ),
                    Marker(
                      point: sos.selectedHospital.position,
                      width: 36.r,
                      height: 36.r,
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppColors.danger,
                          shape: BoxShape.circle,
                          border:
                              Border.all(color: Colors.white, width: 2.5.w),
                        ),
                        child: Icon(Icons.local_hospital_rounded,
                            color: Colors.white, size: 18.sp),
                      ),
                    ),
                  ]),
                ],
              ),
            ),
          ),
          SizedBox(height: 14.h),
          // Driver card
          MCard(
            padding:
                EdgeInsets.symmetric(horizontal: 14.w, vertical: 11.h),
            child: sos.stage == RideStage.searching
                ? Row(
                    children: [
                      SizedBox(
                          width: 22.r,
                          height: 22.r,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.5.w,
                              color: AppColors.danger)),
                      SizedBox(width: 14.w),
                      Expanded(
                        child: Text('Contacting MediRide partners near you…',
                            style: TextStyle(
                                fontSize: 13.5.sp,
                                fontWeight: FontWeight.w600)),
                      ),
                    ],
                  )
                : Row(
                    children: [
                      InitialsAvatar('Marcus Reed',
                          size: 46.r, color: AppColors.danger),
                      SizedBox(width: 12.w),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Driver: Marcus Reed',
                                style: TextStyle(
                                    fontSize: 14.5.sp,
                                    fontWeight: FontWeight.w700)),
                            Text('Toyota Sienna · 7TRX412 · verified partner',
                                style: TextStyle(
                                    fontSize: 12.sp, color: AppColors.muted)),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () =>
                            launchUrl(Uri.parse('tel:14155550149')),
                        icon: Icon(Icons.call_rounded,
                            color: AppColors.danger, size: 24.sp),
                      ),
                    ],
                  ),
          ),
          SizedBox(height: 10.h),
          // Destination + change
          MCard(
            padding:
                EdgeInsets.symmetric(horizontal: 16.w, vertical: 13.h),
            child: Row(
              children: [
                Icon(Icons.local_hospital_rounded,
                    color: AppColors.danger, size: 20.sp),
                SizedBox(width: 10.w),
                Expanded(
                  child: Text(
                      'Destination: ${sos.selectedHospital.name}',
                      style: TextStyle(
                          fontSize: 13.5.sp, fontWeight: FontWeight.w600)),
                ),
                TextButton(
                  onPressed: () => _changeHospital(context),
                  child: Text('Change', style: TextStyle(fontSize: 14.sp)),
                ),
              ],
            ),
          ),
          SizedBox(height: 10.h),
          // Medical ID shared with the driver & ER
          MCard(
            border: Border.all(color: AppColors.danger.withValues(alpha: .3)),
            padding:
                EdgeInsets.symmetric(horizontal: 16.w, vertical: 13.h),
            child: Row(
              children: [
                Icon(Icons.medical_information_rounded,
                    color: AppColors.danger, size: 20.sp),
                SizedBox(width: 10.w),
                Expanded(
                  child: Text(
                    'Medical ID shared: ${p.bloodType} · '
                    'allergies: ${p.allergies.join(", ")} · '
                    '${p.conditions.join(", ")}',
                    style: TextStyle(
                        fontSize: 12.5.sp, color: AppColors.inkSoft),
                  ),
                ),
              ],
            ),
          ),
          if (sos.contactsNotified) ...[
            SizedBox(height: 10.h),
            MCard(
              color: AppColors.successSoft,
              border: Border.all(color: Colors.transparent),
              padding:
                  EdgeInsets.symmetric(horizontal: 16.w, vertical: 13.h),
              child: Row(
                children: [
                  Icon(Icons.check_circle_rounded,
                      color: AppColors.success, size: 20.sp),
                  SizedBox(width: 10.w),
                  Expanded(
                    child: Text(
                        'Contacts notified ✔ '
                        '(${profile.contacts.map((c) => c.name.split(' ').first).join(", ")}) '
                        '· live tracking link sent by text',
                        style: TextStyle(
                            fontSize: 12.5.sp,
                            fontWeight: FontWeight.w600,
                            color: AppColors.success)),
                  ),
                ],
              ),
            ),
          ],
          SizedBox(height: 18.h),
          Center(
            child: TextButton(
              onPressed: () => _confirmCancel(context),
              child: Text('Cancel SOS',
                  style: TextStyle(
                      fontSize: 14.sp,
                      color: AppColors.danger,
                      fontWeight: FontWeight.w600)),
            ),
          ),
          Center(
            child: Text('Fare settles after the trip — payment never blocks '
                'an SOS booking.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.sp, color: AppColors.muted)),
          ),
        ],
      ),
    );
  }

  void _changeHospital(BuildContext context) {
    final sos = context.read<SosProvider>();
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetCtx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Change destination',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            for (final h in MockData.hospitals)
              Material(
                color: Colors.transparent,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.local_hospital_rounded,
                      color: AppColors.danger),
                  title: Text(h.name),
                  subtitle:
                      Text('${h.distanceMiles} mi · ETA ${h.etaMinutes} min'),
                  onTap: () {
                    sos.selectHospital(h);
                    Navigator.pop(sheetCtx);
                    showToast(context,
                        "Driver's navigation updated → ${h.name}");
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _confirmCancel(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Cancel SOS?'),
        content: const Text(
            'This will cancel the emergency ride and notify the driver.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Keep ride')),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogCtx);
              context.read<SosProvider>().cancel();
              Navigator.of(context).popUntil((r) => r.isFirst);
            },
            child: const Text('Cancel SOS',
                style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
  }
}
