import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../providers/location_provider.dart';
import '../../providers/sos_provider.dart';
import '../chat/ai_chat_screen.dart';
import '../home/home_screen.dart';
import '../nearby/nearby_screen.dart';
import '../profile/profile_screen.dart';
import '../reminders/reminders_screen.dart';
import '../sos/sos_screen.dart';

/// Bottom-tab scaffold: home · remind · [SOS] · nearby · profile,
/// plus the floating MedAI button and the 2s long-press SOS trigger.
class PatientShell extends StatefulWidget {
  const PatientShell({super.key});

  @override
  State<PatientShell> createState() => _PatientShellState();
}

class _PatientShellState extends State<PatientShell>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  int index = 0;
  Timer? _sosTimer;
  double _sosProgress = 0.0;
  late AnimationController _sosAnim;

  static const _tabs = [
    HomeScreen(),
    RemindersScreen(),
    NearbyScreen(),
    ProfileScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sosAnim = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    _sosAnim.addListener(() {
      setState(() => _sosProgress = _sosAnim.value);
    });
    // Ask for real location right when the patient reaches the main app —
    // this is what powers "Hospitals near me" / "Pharmacies near me" and
    // the home-screen location label. The system permission dialog carries
    // its own rationale (see Info.plist / AndroidManifest copy).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<LocationProvider>().requestAccess();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sosTimer?.cancel();
    _sosAnim.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Catches the user coming back from Settings after enabling location.
    if (state == AppLifecycleState.resumed) {
      context.read<LocationProvider>().refreshAccessSilently();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _tabs[index],
      floatingActionButton: index == 0
          ? FloatingActionButton.extended(
              heroTag: 'med-ai',
              backgroundColor: AppColors.ai,
              foregroundColor: Colors.white,
              onPressed: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const AiChatScreen())),
              icon: const Icon(Icons.psychology_alt_rounded),
              label: const Text(
                'MedAI',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            )
          : null,
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: const Border(top: BorderSide(color: AppColors.line)),
          boxShadow: [
            BoxShadow(
              color: AppColors.ink.withValues(alpha: .05),
              blurRadius: 12,
            ),
          ],
        ),
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 6.h),
            child: Row(
              children: [
                _navItem(0, Icons.home_rounded, 'Home'),
                _navItem(1, Icons.alarm_rounded, 'Remind'),
                _sosItem(),
                _navItem(2, Icons.map_rounded, 'Nearby'),
                _navItem(3, Icons.person_rounded, 'Profile'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _navItem(int i, IconData icon, String label) {
    final selected = index == i;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => index = i),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 5.h),
              decoration: BoxDecoration(
                color: selected ? AppColors.soft : Colors.transparent,
                borderRadius: BorderRadius.circular(99.r),
              ),
              child: Icon(
                icon,
                size: 24.sp,
                color: selected ? AppColors.primary : AppColors.muted,
              ),
            ),
            SizedBox(height: 2.h),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.sp,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? AppColors.primary : AppColors.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// SOS — a short tap shows a hint; only a 2-second long-press triggers it.
  Widget _sosItem() {
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) {
          _sosAnim.forward();
          _sosTimer = Timer(const Duration(seconds: 2), () {
            context.read<SosProvider>().triggerImmediate();
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SosScreen()),
            );
            _sosAnim.reset();
            _sosProgress = 0;
          });
        },
        onTapUp: (_) {
          _sosTimer?.cancel();
          if (_sosAnim.isAnimating || _sosAnim.value < 1.0) {
            _sosAnim.reverse();
          }
        },
        onTapCancel: () {
          _sosTimer?.cancel();
          _sosAnim.reverse();
        },
        onTap: () {
          if (_sosProgress < 0.1) {
            ScaffoldMessenger.of(context)
              ..clearSnackBars()
              ..showSnackBar(
                const SnackBar(
                  backgroundColor: AppColors.danger,
                  content: Text(
                    'Hold for 2 seconds to trigger SOS',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              );
          }
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 48.w,
                  height: 48.w,
                  child: CircularProgressIndicator(
                    value: _sosProgress,
                    strokeWidth: 3.w,
                    backgroundColor: AppColors.danger.withValues(alpha: .15),
                    valueColor: const AlwaysStoppedAnimation(AppColors.danger),
                  ),
                ),
                Container(
                  width: 40.w,
                  height: 40.w,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppColors.danger, Color(0xFFE0554B)],
                    ),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.danger.withValues(alpha: .4),
                        blurRadius: 10.r,
                        offset: Offset(0, 3.h),
                      ),
                    ],
                  ),
                  child:
                      Icon(Icons.sos_rounded, color: Colors.white, size: 22.sp),
                ),
              ],
            ),
            SizedBox(height: 2.h),
            Text(
              'SOS',
              style: TextStyle(
                fontSize: 10.sp,
                fontWeight: FontWeight.w600,
                color: AppColors.danger,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
