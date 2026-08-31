import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';

import '../theme/app_colors.dart';

/// MediSense's single premium loading indicator.
///
/// A calm, softly-pulsing "fading circle" animation — no harsh spins or
/// flashy motion. Every loading state in the app (full-screen, section,
/// inline) is built from this one widget so the loading experience stays
/// visually consistent everywhere.
class AppSpinner extends StatelessWidget {
  const AppSpinner({super.key, this.size = 34, this.color = AppColors.primary});

  /// Compact variant sized for inline use inside buttons, chips and icons.
  const AppSpinner.inline({
    super.key,
    this.size = 18,
    this.color = Colors.white,
  });

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size.r,
      height: size.r,
      child: SpinKitFadingCircle(
        color: color,
        size: size.r,
        duration: const Duration(milliseconds: 1300),
      ),
    );
  }
}

/// Centered, section-level loading state — used to replace a list, panel,
/// or full screen body while its data is being fetched. Keeps spacing and
/// typography consistent wherever a screen needs to say "loading" instead
/// of showing content yet.
class AppSectionLoader extends StatelessWidget {
  const AppSectionLoader({
    super.key,
    this.label,
    this.padding,
    this.spinnerSize = 34,
    this.color = AppColors.primary,
  });

  final String? label;
  final EdgeInsetsGeometry? padding;
  final double spinnerSize;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding ?? EdgeInsets.symmetric(vertical: 56.h),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppSpinner(size: spinnerSize, color: color),
            if (label != null) ...[
              SizedBox(height: 16.h),
              Text(
                label!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13.sp,
                  fontWeight: FontWeight.w600,
                  color: AppColors.muted,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A small "spinner + caption" row for passive, inline background activity
/// (e.g. an AI insight quietly generating above already-visible content).
/// A calmer, on-brand alternative to a raw [LinearProgressIndicator].
class AppInlineProgressRow extends StatelessWidget {
  const AppInlineProgressRow({
    super.key,
    required this.label,
    this.color = AppColors.primary,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppSpinner.inline(size: 14.r, color: color),
        SizedBox(width: 8.w),
        Flexible(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5.sp,
              fontWeight: FontWeight.w600,
              color: AppColors.muted,
            ),
          ),
        ),
      ],
    );
  }
}
