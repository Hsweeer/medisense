// PATH: lib/features/auth/signup_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/shared_widgets.dart';
import '../../providers/auth_provider.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  bool _obscure = true;
  bool _obscureConfirm = true;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _createAccount() async {
    final name = _name.text.trim();
    final email = _email.text.trim();
    final password = _password.text;
    final confirm = _confirm.text;

    if (name.isEmpty) {
      showToast(context, 'Enter your full name', color: AppColors.danger);
      return;
    }
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
    if (password != confirm) {
      showToast(context, 'Passwords don\'t match', color: AppColors.danger);
      return;
    }

    try {
      await context.read<AuthProvider>().signUp(name, email, password);
      if (mounted) {
        // Pop the signup screen so the AuthWrapper can show the Home screen
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (!mounted) return;
      showToast(context, error.toString(), color: AppColors.danger);
    }
  }

  Future<void> _continueWithGoogle() async {
    try {
      final success = await context.read<AuthProvider>().signInWithGoogle();
      if (mounted && success) {
        // Pop the signup screen if it was pushed
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (!mounted) return;
      showToast(context, error.toString(), color: AppColors.danger);
    }
  }

  Future<void> _continueWithApple() async {
    try {
      final success = await context.read<AuthProvider>().signInWithApple();
      if (mounted && success) {
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (!mounted) return;
      showToast(context, error.toString(), color: AppColors.danger);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final isLoading = auth.isLoading;

    return Stack(
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => FocusScope.of(context).unfocus(),
          child: Scaffold(
            // Same soft teal gradient wash as the login screen — no
            // AppBar, the back arrow sits inline with the brand row
            // below instead, matching the login screen's chip position.
            body: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFFEAF5F2), Color(0xFFDCEEEA)],
                ),
              ),
              child: SafeArea(
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: 20.w,
                    vertical: 4.h,
                  ),
                  // Plain Column, no scroll view — everything below is
                  // sized to fit a single screen without scrolling.
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          GestureDetector(
                            onTap: isLoading
                                ? null
                                : () => Navigator.of(context).pop(),
                            child: Container(
                              width: 34.r,
                              height: 34.r,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.primary.withValues(
                                      alpha: .08,
                                    ),
                                    blurRadius: 10.r,
                                  ),
                                ],
                              ),
                              child: Icon(
                                Icons.arrow_back_rounded,
                                size: 18.sp,
                                color: AppColors.ink,
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 12.h),
                      Center(child: LogoMark(size: 46.r)),
                      SizedBox(height: 6.h),
                      Center(
                        child: RichText(
                          text: TextSpan(
                            style: GoogleFonts.sora(
                              fontSize: 19.sp,
                              fontWeight: FontWeight.w800,
                            ),
                            children: [
                              TextSpan(
                                text: 'Medi',
                                style: TextStyle(color: AppColors.ink),
                              ),
                              TextSpan(
                                text: 'Sense',
                                style: TextStyle(color: AppColors.primary),
                              ),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(height: 10.h),
                      // Floating white card — sign-up form only, same
                      // language as the login screen's card.
                      Container(
                        width: double.infinity,
                        padding: EdgeInsets.fromLTRB(20.w, 16.h, 20.w, 16.h),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24.r),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: .10),
                              blurRadius: 24.r,
                              offset: Offset(0, 10.h),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Center(
                              child: Text(
                                'Create your account',
                                style: GoogleFonts.sora(
                                  fontSize: 17.sp,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.ink,
                                ),
                              ),
                            ),
                            SizedBox(height: 10.h),
                            TextField(
                              controller: _name,
                              textCapitalization: TextCapitalization.words,
                              style: TextStyle(fontSize: 14.sp),
                              decoration: InputDecoration(
                                hintText: 'Full name',
                                hintStyle: TextStyle(fontSize: 13.sp),
                                prefixIcon: Icon(
                                  Icons.person_outline_rounded,
                                  color: AppColors.primary,
                                  size: 19.sp,
                                ),
                              ),
                            ),
                            SizedBox(height: 8.h),
                            TextField(
                              controller: _email,
                              keyboardType: TextInputType.emailAddress,
                              style: TextStyle(fontSize: 14.sp),
                              decoration: InputDecoration(
                                hintText: 'Email address',
                                hintStyle: TextStyle(fontSize: 13.sp),
                                prefixIcon: Icon(
                                  Icons.mail_outline_rounded,
                                  color: AppColors.primary,
                                  size: 19.sp,
                                ),
                              ),
                            ),
                            SizedBox(height: 8.h),
                            TextField(
                              controller: _password,
                              obscureText: _obscure,
                              style: TextStyle(fontSize: 14.sp),
                              decoration: InputDecoration(
                                hintText: 'Password',
                                hintStyle: TextStyle(fontSize: 13.sp),
                                prefixIcon: Icon(
                                  Icons.lock_outline_rounded,
                                  color: AppColors.primary,
                                  size: 19.sp,
                                ),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscure
                                        ? Icons.visibility_off_rounded
                                        : Icons.visibility_rounded,
                                    color: AppColors.muted,
                                    size: 19.sp,
                                  ),
                                  onPressed: () =>
                                      setState(() => _obscure = !_obscure),
                                ),
                              ),
                            ),
                            SizedBox(height: 8.h),
                            TextField(
                              controller: _confirm,
                              obscureText: _obscureConfirm,
                              style: TextStyle(fontSize: 14.sp),
                              decoration: InputDecoration(
                                hintText: 'Confirm password',
                                hintStyle: TextStyle(fontSize: 13.sp),
                                prefixIcon: Icon(
                                  Icons.lock_outline_rounded,
                                  color: AppColors.primary,
                                  size: 19.sp,
                                ),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscureConfirm
                                        ? Icons.visibility_off_rounded
                                        : Icons.visibility_rounded,
                                    color: AppColors.muted,
                                    size: 19.sp,
                                  ),
                                  onPressed: () => setState(
                                    () => _obscureConfirm = !_obscureConfirm,
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(height: 10.h),
                            PrimaryButton(
                              label: 'Create account',
                              icon: Icons.arrow_forward_rounded,
                              onPressed: _createAccount,
                            ),
                            const TextDivider(text: 'OR'),
                            SocialButton(
                              label: 'Sign up with Google',
                              iconWidget: const FaIcon(
                                FontAwesomeIcons.google,
                                color: Color(0xFF4285F4),
                                size: 18,
                              ),
                              onPressed: _continueWithGoogle,
                            ),
                            SizedBox(height: 8.h),
                            SocialButton(
                              label: 'Sign up with Apple',
                              iconWidget: const FaIcon(
                                FontAwesomeIcons.apple,
                                color: Colors.black,
                                size: 20,
                              ),
                              onPressed: _continueWithApple,
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: 10.h),
                      Center(
                        child: GestureDetector(
                          onTap: () => Navigator.of(context).pop(),
                          child: Text.rich(
                            TextSpan(
                              text: 'Already have an account? ',
                              style: TextStyle(
                                fontSize: 12.5.sp,
                                color: AppColors.muted,
                              ),
                              children: [
                                TextSpan(
                                  text: 'Sign in',
                                  style: TextStyle(
                                    fontSize: 12.5.sp,
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      SizedBox(height: 6.h),
                      Center(
                        child: Text.rich(
                          TextSpan(
                            text: 'By creating an account you agree to our ',
                            style: TextStyle(
                              fontSize: 9.5.sp,
                              color: AppColors.muted,
                            ),
                            children: [
                              TextSpan(
                                text: 'Terms',
                                style: TextStyle(
                                  fontSize: 9.5.sp,
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const TextSpan(text: ' and '),
                              TextSpan(
                                text: 'Privacy Policy',
                                style: TextStyle(
                                  fontSize: 9.5.sp,
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const TextSpan(text: '.'),
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
          ),
        ),
        if (isLoading)
          const AppLoadingOverlay(
            title: 'Creating your account',
            message: 'Securing your details and setting things up.',
          ),
      ],
    );
  }
}
