import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../theme/app_colors.dart';

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

/// Soft rounded surface — the app's standard card.
class MCard extends StatelessWidget {
  const MCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.color = AppColors.card,
    this.border,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color color;
  final BoxBorder? border;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(18.r),
        border: border ?? Border.all(color: AppColors.line),
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
