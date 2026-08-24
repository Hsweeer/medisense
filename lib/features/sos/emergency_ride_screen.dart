import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/shared_widgets.dart';
import '../../data/mock/mock_data.dart';
import '../../providers/profile_provider.dart';
import '../../providers/sos_provider.dart';

class EmergencyRideScreen extends StatelessWidget {
  const EmergencyRideScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final sos = context.watch<SosProvider>();
    final profile = context.watch<ProfileProvider>();
    final p = profile.profile;

    final bannerText = switch (sos.stage) {
      RideStage.assigned => 'DRIVER ON THE WAY · ETA ${sos.driverEtaMinutes} min',
      RideStage.pickedUp => 'PICKED UP · Heading to ER',
      RideStage.arrived => 'ARRIVED AT ER ✔',
      _ => 'SEARCHING FOR NEAREST DRIVER…',
    };

    return Scaffold(
      appBar: AppBar(
        title: Text('Emergency Ride', 
          style: GoogleFonts.sora(fontWeight: FontWeight.w700, fontSize: 18.sp)),
        backgroundColor: AppColors.dangerSoft,
        elevation: 0,
        centerTitle: true,
      ),
      backgroundColor: const Color(0xFFFFF7F6),
      body: Column(
        children: [
          // Live status banner
          Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(horizontal: 18.w, vertical: 15.h),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [AppColors.danger, Color(0xFFE0554B)]),
              boxShadow: [
                BoxShadow(
                  color: AppColors.danger.withValues(alpha: 0.2),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                )
              ],
            ),
            child: Row(
              children: [
                const Icon(Icons.emergency_share_rounded, color: Colors.white, size: 24),
                SizedBox(width: 12.w),
                Expanded(
                  child: Text(bannerText,
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 13.sp,
                          letterSpacing: 0.5)),
                ),
              ],
            ),
          ),
          
          Expanded(
            child: ListView(
              padding: EdgeInsets.fromLTRB(20.w, 15.h, 20.w, 24.h),
              children: [
                // Live Map Tracker
                ClipRRect(
                  borderRadius: BorderRadius.circular(20.r),
                  child: Container(
                    height: 180.h,
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.danger.withValues(alpha: 0.1)),
                    ),
                    child: FlutterMap(
                      options: MapOptions(
                        initialCenter: MockData.userLocation,
                        initialZoom: 13.0,
                        interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
                      ),
                      children: [
                        TileLayer(
                          urlTemplate: 'https://basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png',
                          userAgentPackageName: 'com.medisense.medisense_app',
                        ),
                        PolylineLayer(polylines: [
                          Polyline(
                            points: [MockData.userLocation, sos.selectedHospital.position],
                            strokeWidth: 5.w,
                            color: AppColors.danger,
                          ),
                        ]),
                        MarkerLayer(markers: [
                          Marker(
                            point: MockData.userLocation,
                            width: 24.r, height: 24.r,
                            child: Container(
                              decoration: BoxDecoration(
                                color: const Color(0xFF2A6DF4),
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 3.w),
                                boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 10)],
                              ),
                            ),
                          ),
                          Marker(
                            point: sos.selectedHospital.position,
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
                
                SizedBox(height: 16.h),

                // Driver Info Card
                MCard(
                  padding: EdgeInsets.all(16.r),
                  child: sos.stage == RideStage.searching
                      ? Row(
                          children: [
                            const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 3, color: AppColors.danger)),
                            SizedBox(width: 15.w),
                            Text('Locating nearby emergency driver...', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.sp)),
                          ],
                        )
                      : Row(
                          children: [
                            InitialsAvatar('Marcus Reed', size: 48.r, color: AppColors.danger),
                            SizedBox(width: 12.w),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Marcus Reed', style: GoogleFonts.sora(fontWeight: FontWeight.w800, fontSize: 15.sp)),
                                  Text('Toyota Sienna · 7TRX412', style: TextStyle(color: AppColors.muted, fontSize: 12.sp)),
                                ],
                              ),
                            ),
                            IconButton.filled(
                              onPressed: () => launchUrl(Uri.parse('tel:911')),
                              icon: const Icon(Icons.call_rounded, size: 20),
                              style: IconButton.styleFrom(backgroundColor: AppColors.danger),
                            ),
                          ],
                        ),
                ),

                SizedBox(height: 12.h),

                // Destination Card
                MCard(
                  padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
                  child: Row(
                    children: [
                      const Icon(Icons.location_on_rounded, color: AppColors.danger, size: 22),
                      SizedBox(width: 10.w),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('DESTINATION', style: TextStyle(fontSize: 10.sp, fontWeight: FontWeight.w800, color: AppColors.muted, letterSpacing: 1)),
                            Text(sos.selectedHospital.name, style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                SizedBox(height: 12.h),

                // Medical ID Sharing Confirmation
                MCard(
                  color: AppColors.danger.withValues(alpha: 0.04),
                  border: Border.all(color: AppColors.danger.withValues(alpha: 0.2)),
                  padding: EdgeInsets.all(16.r),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.health_and_safety_rounded, color: AppColors.danger, size: 20),
                          SizedBox(width: 8.w),
                          Text('MEDICAL ID SHARED', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 11.sp, letterSpacing: 0.5)),
                        ],
                      ),
                      SizedBox(height: 8.h),
                      Text(
                        'Responders can see: ${p.bloodType} blood type, ${p.allergies.isNotEmpty ? p.allergies.join(", ") : "no allergies"}, and ${p.conditions.isNotEmpty ? p.conditions.join(", ") : "no conditions"}.',
                        style: TextStyle(fontSize: 12.sp, color: AppColors.inkSoft, height: 1.4),
                      ),
                    ],
                  ),
                ),

                if (sos.contactsNotified) ...[
                  SizedBox(height: 12.h),
                  MCard(
                    color: AppColors.success.withValues(alpha: 0.05),
                    border: Border.all(color: AppColors.success.withValues(alpha: 0.2)),
                    padding: EdgeInsets.all(16.r),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 20),
                        SizedBox(width: 10.w),
                        Expanded(
                          child: Text(
                            'Emergency contacts have been texted your live location tracker.',
                            style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w600, color: AppColors.success),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                SizedBox(height: 24.h),

                // Bottom Action
                Center(
                  child: TextButton(
                    onPressed: () => _confirmCancel(context),
                    style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                    child: Text('CANCEL SOS', style: GoogleFonts.sora(fontWeight: FontWeight.w800, fontSize: 14.sp, letterSpacing: 1)),
                  ),
                ),
                SizedBox(height: 8.h),
                Text(
                  'Your safety is our priority. A 911 call prompt will appear if the driver does not arrive within the ETA.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11.sp, color: AppColors.muted, height: 1.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _confirmCancel(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20.r)),
        title: Text('Cancel Emergency?', style: GoogleFonts.sora(fontWeight: FontWeight.w800)),
        content: const Text('Only cancel if you are safe. This will alert the driver and your emergency contacts.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('STAY ON TRIP')),
          FilledButton(
            onPressed: () {
              context.read<SosProvider>().cancel();
              Navigator.popUntil(context, (route) => route.isFirst);
            },
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('YES, I AM SAFE'),
          ),
        ],
      ),
    );
  }
}
