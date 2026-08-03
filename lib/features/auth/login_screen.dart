import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/shared_widgets.dart';
import '../../providers/auth_provider.dart';
import '../../providers/profile_provider.dart';
import '../shell/patient_shell.dart';
import 'forgot_password_screen.dart';
import 'signup_screen.dart';

// import 'otp_screen.dart'; // kept for when phone login is re-enabled

/// Login with built-in marketing: rotating value-prop hero, trust strip,
/// then email/password sign-in for existing accounts. New users are sent
/// to [SignupScreen] via the link below the form.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _page = PageController();
  int _slide = 0;
  Timer? _auto;
  bool _submitting = false;
  bool _obscure = true;

  static const _slides = [
    (
      Icons.psychology_alt_rounded,
      'Meet MedAI',
      'A personal health assistant that reads your labs, photos, and voice '
          'notes — and learns your health story over time.',
    ),
    (
      Icons.map_rounded,
      'Care, mapped around you',
      'Find nearby hospitals and pharmacies on a live map with one-tap '
          'directions when minutes matter.',
    ),
    (
      Icons.sos_rounded,
      'Emergency SOS built in',
      'One tap calls 911 and alerts your emergency contacts with your '
          'location and medical profile.',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _auto = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!_page.hasClients) return;
      final next = (_slide + 1) % _slides.length;
      _page.animateToPage(
        next,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  void dispose() {
    _auto?.cancel();
    _email.dispose();
    _password.dispose();
    _page.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    final email = _email.text.trim();
    final password = _password.text;

    if (!email.contains('@') || !email.contains('.')) {
      showToast(
        context,
        'Enter a valid email address',
        color: AppColors.danger,
      );
      return;
    }
    if (password.length < 6) {
      showToast(
        context,
        'Password must be at least 6 characters',
        color: AppColors.danger,
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      await context.read<AuthProvider>().signIn(email, password);
      // No manual navigation here! The AuthWrapper in main.dart handles it.
    } catch (error) {
      if (!mounted) return;
      showToast(context, error.toString(), color: AppColors.danger);
      setState(() => _submitting = false);
    }
  }

  Future<void> _continueWithGoogle() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    try {
      final success = await context.read<AuthProvider>().signInWithGoogle();
      if (!mounted) return;
      
      if (!success) {
        setState(() => _submitting = false);
      }
      // If success, AuthWrapper automatically switches to PatientShell
    } catch (error) {
      if (!mounted) return;
      setState(() => _submitting = false);
      showToast(context, error.toString(), color: AppColors.danger);
    }
  }

  Future<void> _continueWithApple() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    try {
      final success = await context.read<AuthProvider>().signInWithApple();
      if (!mounted) return;

      if (!success) {
        setState(() => _submitting = false);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _submitting = false);
      showToast(context, error.toString(), color: AppColors.danger);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        body: SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(24.w, 18.h, 24.w, 24.h),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    LogoMark(size: 42.r),
                    SizedBox(width: 10.w),
                    Expanded(
                      child: Text(
                        'MediSense',
                        style: GoogleFonts.sora(
                          fontSize: 20.sp,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    SizedBox(width: 8.w),
                    const MChip(
                      'US · English',
                      background: AppColors.soft,
                      foreground: AppColors.onSoft,
                    ),
                  ],
                ),
                SizedBox(height: 26.h),
                Text(
                  'Your health,\nunderstood.',
                  style: GoogleFonts.sora(
                    fontSize: 32.sp,
                    fontWeight: FontWeight.w700,
                    height: 1.15,
                  ),
                ),
                SizedBox(height: 8.h),
                Text(
                  'AI guidance, nearby care, and emergency help — in one app.',
                  style: TextStyle(fontSize: 14.5.sp, color: AppColors.muted),
                ),
                SizedBox(height: 22.h),
                // Rotating value-prop hero.
                SizedBox(
                  height: 148.h,
                  child: PageView.builder(
                    controller: _page,
                    itemCount: _slides.length,
                    onPageChanged: (i) => setState(() => _slide = i),
                    itemBuilder: (_, i) {
                      final s = _slides[i];
                      return Container(
                        margin: EdgeInsets.symmetric(horizontal: 2.w),
                        padding: EdgeInsets.all(18.r),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: i == 2
                                ? [const Color(0xFF8A2F28), AppColors.danger]
                                : i == 1
                                ? AppColors.gradient
                                : AppColors.aiGradient,
                          ),
                          borderRadius: BorderRadius.circular(20.r),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 52.r,
                              height: 52.r,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: .18),
                                borderRadius: BorderRadius.circular(16.r),
                              ),
                              child: Icon(s.$1, color: Colors.white, size: 28.sp),
                            ),
                            SizedBox(width: 14.w),
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    s.$2,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.sora(
                                      fontSize: 16.5.sp,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  ),
                                  SizedBox(height: 5.h),
                                  Text(
                                    s.$3,
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12.5.sp,
                                      height: 1.35,
                                      color: Colors.white.withValues(
                                        alpha: .88,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                SizedBox(height: 12.h),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < _slides.length; i++)
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        margin: EdgeInsets.symmetric(horizontal: 3.w),
                        width: i == _slide ? 22.w : 7.w,
                        height: 7.h,
                        decoration: BoxDecoration(
                          color: i == _slide
                              ? AppColors.primary
                              : AppColors.line,
                          borderRadius: BorderRadius.circular(4.r),
                        ),
                      ),
                  ],
                ),
                SizedBox(height: 18.h),
                // Trust strip — static social proof, costs nothing.
                MCard(
                  padding: EdgeInsets.symmetric(
                    horizontal: 14.w,
                    vertical: 12.h,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: const [
                      _TrustStat(value: '4.9★', label: 'App rating'),
                      _StatDivider(),
                      _TrustStat(value: '120k+', label: 'Members'),
                      _StatDivider(),
                      _TrustStat(value: 'Free', label: 'To start'),
                    ],
                  ),
                ),
                SizedBox(height: 22.h),
                Text(
                  'Sign in with your email',
                  style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w700),
                ),
                SizedBox(height: 4.h),
                Text(
                  'Enter the email and password for your existing account.',
                  style: TextStyle(fontSize: 11.5.sp, color: AppColors.muted),
                ),
                SizedBox(height: 10.h),
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  style: TextStyle(fontSize: 15.sp),
                  decoration: InputDecoration(
                    hintText: 'you@example.com',
                    hintStyle: TextStyle(fontSize: 14.sp),
                    prefixIcon: Icon(
                      Icons.mail_outline_rounded,
                      color: AppColors.muted,
                      size: 20.sp,
                    ),
                  ),
                ),
                SizedBox(height: 12.h),
                TextField(
                  controller: _password,
                  obscureText: _obscure,
                  style: TextStyle(fontSize: 15.sp),
                  decoration: InputDecoration(
                    hintText: 'Password',
                    hintStyle: TextStyle(fontSize: 14.sp),
                    prefixIcon: Icon(
                      Icons.lock_outline_rounded,
                      color: AppColors.muted,
                      size: 20.sp,
                    ),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscure
                            ? Icons.visibility_off_rounded
                            : Icons.visibility_rounded,
                        color: AppColors.muted,
                        size: 20.sp,
                      ),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                ),
                SizedBox(height: 8.h),
                Align(
                  alignment: Alignment.centerRight,
                  child: GestureDetector(
                    onTap: _submitting
                        ? null
                        : () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const ForgotPasswordScreen(),
                            ),
                          ),
                    child: Text(
                      'Forgot password?',
                      style: TextStyle(
                        fontSize: 13.sp,
                        color: AppColors.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                SizedBox(height: 6.h),
                PrimaryButton(
                  label: _submitting ? 'Please wait…' : 'Sign in',
                  icon: _submitting ? null : Icons.arrow_forward_rounded,
                  onPressed: _submitting ? null : _continue,
                ),
                const TextDivider(text: 'OR'),
                SocialButton(
                  label: _submitting ? 'Connecting Google…' : 'Continue with Google',
                  iconWidget: _submitting 
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary))
                    : Image.network(
                        'https://upload.wikimedia.org/wikipedia/commons/thumb/c/c1/Google_\"G\"_logo.svg/1200px-Google_\"G\"_logo.svg.png',
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => Text('G', 
                          style: GoogleFonts.sora(fontWeight: FontWeight.w900, color: Colors.blue)),
                      ),
                  onPressed: _submitting ? null : _continueWithGoogle,
                ),
                SizedBox(height: 12.h),
                SocialButton(
                  label: _submitting ? 'Connecting Apple…' : 'Continue with Apple',
                  iconWidget: _submitting 
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                    : Image.network(
                        'https://upload.wikimedia.org/wikipedia/commons/thumb/f/fa/Apple_logo_black.svg/1667px-Apple_logo_black.svg.png',
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const Icon(Icons.phone_iphone_rounded, color: Colors.black),
                      ),
                  onPressed: _submitting ? null : _continueWithApple,
                ),
                SizedBox(height: 24.h),
                Center(
                  child: GestureDetector(
                    onTap: _submitting
                        ? null
                        : () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const SignupScreen(),
                            ),
                          ),
                    child: Text.rich(
                      TextSpan(
                        text: "New here? ",
                        style: TextStyle(
                          fontSize: 13.sp,
                          color: AppColors.muted,
                        ),
                        children: [
                          TextSpan(
                            text: 'Create an account',
                            style: TextStyle(
                              fontSize: 13.sp,
                              color: AppColors.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 16),
                Center(
                  child: Text.rich(
                    TextSpan(
                      text: 'By continuing you agree to our ',
                      style: TextStyle(
                        fontSize: 11.5.sp,
                        color: AppColors.muted,
                      ),
                      children: [
                        TextSpan(
                          text: 'Terms',
                          style: TextStyle(
                            fontSize: 11.5.sp,
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const TextSpan(text: ' and '),
                        TextSpan(
                          text: 'Privacy Policy',
                          style: TextStyle(
                            fontSize: 11.5.sp,
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const TextSpan(
                          text: '. MedAI offers guidance, not a diagnosis.',
                        ),
                      ],
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TrustStat extends StatelessWidget {
  const _TrustStat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: GoogleFonts.sora(
            fontSize: 16.sp,
            fontWeight: FontWeight.w700,
            color: AppColors.primary,
          ),
        ),
        SizedBox(height: 2.h),
        Text(
          label,
          style: TextStyle(fontSize: 11.sp, color: AppColors.muted),
        ),
      ],
    );
  }
}

class _StatDivider extends StatelessWidget {
  const _StatDivider();

  @override
  Widget build(BuildContext context) =>
      Container(width: 1.w, height: 28.h, color: AppColors.line);
}
