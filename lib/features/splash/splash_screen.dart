import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/widgets/shared_widgets.dart';

/// Purely visual brand splash — deep teal gradient, breathing pulse logo,
/// wordmark reveal. No business logic here (handled by AuthWrapper).
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..forward();
  late final AnimationController _breathe = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _intro.dispose();
    _breathe.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fade = CurvedAnimation(parent: _intro, curve: Curves.easeOutCubic);
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF06413A), Color(0xFF0C8577), Color(0xFF0FA090)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const Spacer(flex: 3),
              // Breathing logo with soft halo rings.
              AnimatedBuilder(
                animation: _breathe,
                builder: (_, child) {
                  final t = Curves.easeInOut.transform(_breathe.value);
                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      for (var ring = 0; ring < 2; ring++)
                        Container(
                          width: (130 + ring * 46 + t * 14).r,
                          height: (130 + ring * 46 + t * 14).r,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white.withValues(
                                alpha: .16 - ring * .07,
                              ),
                              width: 1.4.r,
                            ),
                          ),
                        ),
                      ScaleTransition(
                        scale: Tween(begin: .7, end: 1.0).animate(fade),
                        child: FadeTransition(
                          opacity: fade,
                          child: const LogoMark(size: 96, onDark: true),
                        ),
                      ),
                    ],
                  );
                },
              ),
              SizedBox(height: 34.h),
              FadeTransition(
                opacity: fade,
                child: SlideTransition(
                  position: Tween(
                    begin: const Offset(0, .35),
                    end: Offset.zero,
                  ).animate(fade),
                  child: Column(
                    children: [
                      Text(
                        'MediSense',
                        style: GoogleFonts.sora(
                          fontSize: 36.sp,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          letterSpacing: -.5,
                        ),
                      ),
                      SizedBox(height: 8.h),
                      Text(
                        'Smart care. Anywhere.',
                        style: GoogleFonts.ibmPlexSans(
                          fontSize: 15.sp,
                          color: Colors.white.withValues(alpha: .82),
                          letterSpacing: .4,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Spacer(flex: 3),
              // Indeterminate shimmer bar.
              AnimatedBuilder(
                animation: _breathe,
                builder: (_, child) => Container(
                  width: 132.w,
                  height: 4.h,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .18),
                    borderRadius: BorderRadius.circular(4.r),
                  ),
                  child: Align(
                    alignment: Alignment(-1 + 2 * _breathe.value, 0),
                    child: Container(
                      width: 48.w,
                      height: 4.h,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(4.r),
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(height: 26.h),
              Text(
                'HIPAA-conscious design · Your data stays yours',
                style: TextStyle(
                  fontSize: 11.5.sp,
                  color: Colors.white.withValues(alpha: .55),
                ),
              ),
              SizedBox(height: 22.h),
            ],
          ),
        ),
      ),
    );
  }
}
