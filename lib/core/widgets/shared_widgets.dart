import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../theme/app_colors.dart';
import '../services/loading_overlay_controller.dart';
import 'app_loading.dart';

/// Big filled call-to-action used at the bottom of most flows.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.color = AppColors.primary,
    this.icon,
    this.subLabel,
  });

  final String label;
  final VoidCallback? onPressed;
  final Color color;
  final IconData? icon;
  final String? subLabel;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: color,
          disabledBackgroundColor: color.withValues(alpha: .35),
          foregroundColor: Colors.white,
          padding: EdgeInsets.symmetric(vertical: 16.h),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14.r),
          ),
          textStyle: TextStyle(
            fontSize: 15.sp,
            fontWeight: FontWeight.w700,
            letterSpacing: .3,
          ),
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 20.sp),
                  SizedBox(width: 8.w),
                ],
                Flexible(child: Text(label, textAlign: TextAlign.center)),
              ],
            ),
            if (subLabel != null)
              Padding(
                padding: EdgeInsets.only(top: 2.h),
                child: Text(
                  subLabel!,
                  style: TextStyle(
                    fontSize: 11.sp,
                    fontWeight: FontWeight.w400,
                    color: Colors.white.withValues(alpha: .85),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Outlined button for secondary actions.
class SecondaryButton extends StatelessWidget {
  const SecondaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.color = AppColors.primary,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          side: BorderSide(color: color.withValues(alpha: .4), width: 1.5.w),
          padding: EdgeInsets.symmetric(vertical: 16.h),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14.r),
          ),
          textStyle: TextStyle(
            fontSize: 15.sp,
            fontWeight: FontWeight.w700,
            letterSpacing: .3,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 20.sp),
              SizedBox(width: 8.w),
            ],
            Flexible(child: Text(label, textAlign: TextAlign.center)),
          ],
        ),
      ),
    );
  }
}

/// Professional social sign-in button (Google, Apple, etc.)
class SocialButton extends StatelessWidget {
  const SocialButton({
    super.key,
    required this.label,
    required this.iconWidget,
    required this.onPressed,
    this.color = Colors.white,
    this.textColor = AppColors.ink,
  });

  final String label;
  final Widget iconWidget;
  final VoidCallback? onPressed;
  final Color color;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: textColor,
          side: BorderSide(color: AppColors.line, width: 1.w),
          padding: EdgeInsets.symmetric(vertical: 14.h),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14.r),
          ),
          elevation: 0,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(width: 18.sp, height: 18.sp, child: iconWidget),
            SizedBox(width: 12.w),
            Text(
              label,
              style: TextStyle(fontSize: 14.5.sp, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

/// Horizontal divider with text in the middle (e.g. "OR")
class TextDivider extends StatelessWidget {
  const TextDivider({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 20.h),
      child: Row(
        children: [
          const Expanded(child: Divider(color: AppColors.line)),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 14.w),
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12.sp,
                fontWeight: FontWeight.w600,
                color: AppColors.muted,
              ),
            ),
          ),
          const Expanded(child: Divider(color: AppColors.line)),
        ],
      ),
    );
  }
}

/// Soft rounded surface — the app's standard card.
class MCard extends StatelessWidget {
  const MCard({
    super.key,
    required this.child,
    this.padding,
    this.color = AppColors.card,
    this.border,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final Color color;
  final BoxBorder? border;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      width: double.infinity,
      padding: padding ?? EdgeInsets.all(16.r),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(18.r),
        border: border ?? Border.all(color: AppColors.line, width: 1.w),
        boxShadow: [
          BoxShadow(
            color: AppColors.ink.withValues(alpha: .04),
            blurRadius: 14.r,
            offset: Offset(0, 4.h),
          ),
        ],
      ),
      child: child,
    );
    if (onTap == null) return card;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: card,
    );
  }
}

/// Small rounded status/label chip.
class MChip extends StatelessWidget {
  const MChip(
    this.label, {
    super.key,
    this.background = AppColors.paper,
    this.foreground = AppColors.muted,
    this.icon,
    this.onTap,
  });

  final String label;
  final Color background;
  final Color foreground;
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 5.h),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(99.r),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 13.sp, color: foreground),
              SizedBox(width: 4.w),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 12.sp,
                fontWeight: FontWeight.w600,
                color: foreground,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Section heading with optional trailing action.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.action, this.onAction});

  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: 10.h, top: 4.h),
      child: Row(
        children: [
          Expanded(
            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
          if (action != null)
            GestureDetector(
              onTap: onAction,
              child: Text(
                action!,
                style: TextStyle(
                  fontSize: 13.sp,
                  fontWeight: FontWeight.w600,
                  color: AppColors.muted,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Circular avatar. Shows the user's photo when [imageUrl] is provided,
/// otherwise falls back to a gradient initials badge.
class InitialsAvatar extends StatelessWidget {
  const InitialsAvatar(
    this.name, {
    super.key,
    this.size = 46,
    this.color,
    this.imageUrl,
  });

  final String name;
  final double size;
  final Color? color;

  /// Optional network image URL (e.g. Firebase Storage download URL).
  /// When null or empty, the initials fallback is shown instead.
  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    if (imageUrl != null && imageUrl!.isNotEmpty) {
      return ClipOval(
        child: Image.network(
          imageUrl!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          // If the URL fails to load, fall back to initials rather than
          // showing a broken-image icon.
          errorBuilder: (context, error, stackTrace) => _initialsBadge(context),
        ),
      );
    }
    return _initialsBadge(context);
  }

  Widget _initialsBadge(BuildContext context) {
    final c = color ?? AppColors.primary;
    final initials = name
        .trim()
        .split(RegExp(r'\s+'))
        .take(2)
        .map((w) => w.isEmpty ? '' : w[0])
        .join()
        .toUpperCase();
    return Container(
      width: size.r,
      height: size.r,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [c.withValues(alpha: .85), c],
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: TextStyle(
          color: Colors.white,
          fontSize: (size * .34).sp,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// The MediSense logo mark — pulse line inside a rounded-square badge.
class LogoMark extends StatelessWidget {
  const LogoMark({super.key, this.size = 64, this.onDark = false});

  final double size;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size.r,
      height: size.r,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: onDark
              ? [Colors.white, const Color(0xFFE6F5F2)]
              : AppColors.gradient,
        ),
        borderRadius: BorderRadius.circular(size * .3),
        boxShadow: [
          BoxShadow(
            color: (onDark ? Colors.black : AppColors.primary).withValues(
              alpha: .25,
            ),
            blurRadius: size * .3,
            offset: Offset(0, size * .1),
          ),
        ],
      ),
      child: CustomPaint(
        painter: _PulsePainter(
          color: onDark ? AppColors.primary : Colors.white,
        ),
      ),
    );
  }
}

class _PulsePainter extends CustomPainter {
  const _PulsePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * .085
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final w = size.width;
    final h = size.height;
    final path = Path()
      ..moveTo(w * .16, h * .52)
      ..lineTo(w * .36, h * .52)
      ..lineTo(w * .45, h * .30)
      ..lineTo(w * .57, h * .72)
      ..lineTo(w * .65, h * .52)
      ..lineTo(w * .84, h * .52);
    canvas.drawPath(path, p);
  }

  @override
  bool shouldRepaint(covariant _PulsePainter old) => old.color != color;
}

/// Drag handle shown at the top of every modal bottom sheet in the app —
/// one consistent visual cue, everywhere, that the sheet is draggable.
class SheetHandle extends StatelessWidget {
  const SheetHandle({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 40.w,
        height: 4.5.h,
        decoration: BoxDecoration(
          color: AppColors.line,
          borderRadius: BorderRadius.circular(99.r),
        ),
      ),
    );
  }
}

/// Icon-badge header used at the top of bottom sheets across the app —
/// a soft gradient icon badge, a bold title, and an optional one-line
/// subtitle, so every sheet opens with the same premium, consistent moment.
class SheetHeader extends StatelessWidget {
  const SheetHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.color = AppColors.primary,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Color color;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (icon != null) ...[
          Container(
            width: 46.r,
            height: 46.r,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  color.withValues(alpha: .18),
                  color.withValues(alpha: .07),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(15.r),
              border: Border.all(color: color.withValues(alpha: .15)),
            ),
            child: Icon(icon, color: color, size: 22.sp),
          ),
          SizedBox(width: 14.w),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 19.sp,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -.3,
                  color: AppColors.ink,
                ),
              ),
              if (subtitle != null) ...[
                SizedBox(height: 3.h),
                Text(
                  subtitle!,
                  style: TextStyle(
                    fontSize: 12.5.sp,
                    height: 1.4,
                    color: AppColors.muted,
                  ),
                ),
              ],
            ],
          ),
        ),
        ?trailing,
      ],
    );
  }
}

/// Professional confirmation dialog used across the app for destructive
/// actions like sign out, delete, and clear history.
class AppDialog {
  static Future<bool> confirm({
    required BuildContext context,
    required String title,
    required String message,
    required String confirmText,
    String cancelText = 'Cancel',
    bool destructive = false,
    IconData icon = Icons.info_outline_rounded,
    Color? accentColor,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        final color =
            accentColor ?? (destructive ? AppColors.danger : AppColors.primary);
        return Dialog(
          insetPadding: EdgeInsets.symmetric(horizontal: 22.w),
          backgroundColor: Colors.transparent,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28.r),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(
                padding: EdgeInsets.fromLTRB(22.r, 22.r, 22.r, 18.r),
                decoration: BoxDecoration(
                  color: AppColors.card.withValues(alpha: .96),
                  borderRadius: BorderRadius.circular(28.r),
                  border: Border.all(color: Colors.white.withValues(alpha: .8)),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.ink.withValues(alpha: .18),
                      blurRadius: 32.r,
                      offset: Offset(0, 16.h),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 64.r,
                      height: 64.r,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [color.withValues(alpha: .18), color.withValues(alpha: .07)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        shape: BoxShape.circle,
                        border: Border.all(color: color.withValues(alpha: .15)),
                      ),
                      child: Icon(icon, color: color, size: 30.sp),
                    ),
                    SizedBox(height: 17.h),
                    Text(title, textAlign: TextAlign.center, style: TextStyle(fontSize: 20.sp, fontWeight: FontWeight.w800, letterSpacing: -.3, color: AppColors.ink)),
                    SizedBox(height: 9.h),
                    Text(message, textAlign: TextAlign.center, style: TextStyle(fontSize: 14.sp, height: 1.5, color: AppColors.muted)),
                    SizedBox(height: 22.h),
                    Divider(height: 1, color: AppColors.line.withValues(alpha: .8)),
                    SizedBox(height: 14.h),
                    Row(
                      children: [
                        Expanded(child: OutlinedButton(onPressed: () => Navigator.of(ctx).pop(false), style: OutlinedButton.styleFrom(foregroundColor: AppColors.ink, side: BorderSide(color: AppColors.line, width: 1.2.w), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14.r)), padding: EdgeInsets.symmetric(vertical: 14.h), textStyle: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w700)), child: Text(cancelText))),
                        SizedBox(width: 12.w),
                        Expanded(child: FilledButton(onPressed: () => Navigator.of(ctx).pop(true), style: FilledButton.styleFrom(backgroundColor: color, foregroundColor: Colors.white, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14.r)), padding: EdgeInsets.symmetric(vertical: 14.h), textStyle: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w700)), child: Text(confirmText))),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );

    return confirmed ?? false;
  }
}

/// Branded, blocking progress surface for authentication and remote actions.
class AppLoadingOverlay extends StatefulWidget {
  const AppLoadingOverlay({
    super.key,
    this.title = 'Connecting securely',
    this.message = 'Please wait while we prepare your account.',
  });

  final String title;
  final String message;

  @override
  State<AppLoadingOverlay> createState() => _AppLoadingOverlayState();
}

class _AppLoadingOverlayState extends State<AppLoadingOverlay> {
  @override
  void initState() {
    super.initState();
    // UI-level only: lets other UI (e.g. the SOS overlay button) know a
    // blocking loader is on screen, without touching Provider/business state.
    LoadingOverlayController.to.register();
  }

  @override
  void dispose() {
    LoadingOverlayController.to.unregister();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
      child: ColoredBox(
        color: AppColors.ink.withValues(alpha: .5),
        child: Center(
          child: Container(
            width: 280.w,
            margin: EdgeInsets.symmetric(horizontal: 28.w),
            padding: EdgeInsets.fromLTRB(24.r, 25.r, 24.r, 22.r),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.card, AppColors.soft.withValues(alpha: .72)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              borderRadius: BorderRadius.circular(26.r),
              border: Border.all(color: AppColors.primary.withValues(alpha: .2)),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .22), blurRadius: 30.r, offset: Offset(0, 14.h))],
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 68.r,
                height: 68.r,
                decoration: const BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: AppColors.gradient, begin: Alignment.topLeft, end: Alignment.bottomRight)),
                child: Padding(
                  padding: EdgeInsets.all(17.r),
                  child: const AppSpinner.inline(size: 34, color: Colors.white),
                ),
              ),
              SizedBox(height: 19.h),
              Text(widget.title, textAlign: TextAlign.center, style: TextStyle(fontSize: 17.sp, fontWeight: FontWeight.w800, color: AppColors.ink, decoration: TextDecoration.none)),
              SizedBox(height: 7.h),
              Text(widget.message, textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5.sp, height: 1.45, color: AppColors.muted, decoration: TextDecoration.none)),
              SizedBox(height: 19.h),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
                decoration: BoxDecoration(
                  color: AppColors.soft,
                  borderRadius: BorderRadius.circular(99.r),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.lock_rounded,
                      size: 14.sp,
                      color: AppColors.primaryDark,
                    ),
                    SizedBox(width: 6.w),
                    Text(
                      'Your information stays protected',
                      style: TextStyle(
                        fontSize: 11.sp,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primaryDark,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ],
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Standard toast helper.
void showToast(
  BuildContext context,
  String message, {
  Color color = AppColors.ink,
}) {
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        backgroundColor: color,
        content: Text(
          message,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
}