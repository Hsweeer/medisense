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

/// Bottom-tab scaffold: home · remind · [SOS] · nearby · profile.
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
      duration: const Duration(seconds: 1),
    );
    _sosAnim.addListener(() {
      setState(() => _sosProgress = _sosAnim.value);
    });

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
    if (state == AppLifecycleState.resumed) {
      context.read<LocationProvider>().refreshAccessSilently();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: index,
        children: _tabs,
      ),
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
                _sosItem(), // Always visible now
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

  Widget _sosItem() {
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          context.read<SosProvider>().triggerImmediate();
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const SosScreen()),
          );
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40.w,
              height: 40.w,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.danger, Color(0xFFE0554B)],
                ),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.sos_rounded, color: Colors.white, size: 22.sp),
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
