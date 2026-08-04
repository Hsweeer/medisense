import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
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
      showToast(context, 'Enter a valid email address', color: AppColors.danger);
      return;
    }
    if (password.length < 6) {
      showToast(context, 'Password must be at least 6 characters', color: AppColors.danger);
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
            appBar: AppBar(
              leading: BackButton(
                onPressed: isLoading ? null : () => Navigator.of(context).pop(),
              ),
            ),
            body: SafeArea(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(24.w, 4.h, 24.w, 24.h),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        LogoMark(size: 42.r),
                        SizedBox(width: 10.w),
                        Text('MediSense',
                            style: GoogleFonts.sora(
                                fontSize: 20.sp, fontWeight: FontWeight.w700)),
                      ],
                    ),
                    SizedBox(height: 26.h),
                    Text('Create your\naccount',
                        style: GoogleFonts.sora(
                            fontSize: 32.sp,
                            fontWeight: FontWeight.w700,
                            height: 1.15)),
                    SizedBox(height: 8.h),
                    Text(
                      'Takes less than a minute. You\'ll land straight on your '
                      'home dashboard once you\'re done.',
                      style: TextStyle(fontSize: 14.5.sp, color: AppColors.muted),
                    ),
                    SizedBox(height: 26.h),
                    Text('Full name',
                        style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700)),
                    SizedBox(height: 8.h),
                    TextField(
                      controller: _name,
                      textCapitalization: TextCapitalization.words,
                      style: TextStyle(fontSize: 15.sp),
                      decoration: InputDecoration(
                        hintText: 'Jordan Blake',
                        hintStyle: TextStyle(fontSize: 14.sp),
                        prefixIcon: Icon(Icons.person_outline_rounded,
                            color: AppColors.muted, size: 20.sp),
                      ),
                    ),
                    SizedBox(height: 16.h),
                    Text('Email',
                        style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700)),
                    SizedBox(height: 8.h),
                    TextField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      style: TextStyle(fontSize: 15.sp),
                      decoration: InputDecoration(
                        hintText: 'you@example.com',
                        hintStyle: TextStyle(fontSize: 14.sp),
                        prefixIcon: Icon(Icons.mail_outline_rounded,
                            color: AppColors.muted, size: 20.sp),
                      ),
                    ),
                    SizedBox(height: 16.h),
                    Text('Password',
                        style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700)),
                    SizedBox(height: 8.h),
                    TextField(
                      controller: _password,
                      obscureText: _obscure,
                      style: TextStyle(fontSize: 15.sp),
                      decoration: InputDecoration(
                        hintText: 'At least 6 characters',
                        hintStyle: TextStyle(fontSize: 14.sp),
                        prefixIcon: Icon(Icons.lock_outline_rounded,
                            color: AppColors.muted, size: 20.sp),
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
                    SizedBox(height: 16.h),
                    Text('Confirm password',
                        style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700)),
                    SizedBox(height: 8.h),
                    TextField(
                      controller: _confirm,
                      obscureText: _obscureConfirm,
                      style: TextStyle(fontSize: 15.sp),
                      decoration: InputDecoration(
                        hintText: 'Re-enter your password',
                        hintStyle: TextStyle(fontSize: 14.sp),
                        prefixIcon: Icon(Icons.lock_outline_rounded,
                            color: AppColors.muted, size: 20.sp),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscureConfirm
                                ? Icons.visibility_off_rounded
                                : Icons.visibility_rounded,
                            color: AppColors.muted,
                            size: 20.sp,
                          ),
                          onPressed: () =>
                              setState(() => _obscureConfirm = !_obscureConfirm),
                        ),
                      ),
                    ),
                    SizedBox(height: 22.h),
                    PrimaryButton(
                      label: 'Create account',
                      icon: Icons.arrow_forward_rounded,
                      onPressed: _createAccount,
                    ),
                    const TextDivider(text: 'OR'),
                    SocialButton(
                      label: 'Sign up with Google',
                      iconWidget: Image.network(
                        'https://upload.wikimedia.org/wikipedia/commons/thumb/c/c1/Google_\"G\"_logo.svg/1200px-Google_\"G\"_logo.svg.png',
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => Text('G', 
                          style: GoogleFonts.sora(fontWeight: FontWeight.w900, color: Colors.blue)),
                      ),
                      onPressed: _continueWithGoogle,
                    ),
                    SizedBox(height: 12.h),
                    SocialButton(
                      label: 'Sign up with Apple',
                      iconWidget: Image.network(
                        'https://upload.wikimedia.org/wikipedia/commons/thumb/f/fa/Apple_logo_black.svg/1667px-Apple_logo_black.svg.png',
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const Icon(Icons.phone_iphone_rounded, color: Colors.black),
                      ),
                      onPressed: _continueWithApple,
                    ),
                    SizedBox(height: 24.h),
                    Center(
                      child: GestureDetector(
                        onTap: () => Navigator.of(context).pop(),
                        child: Text.rich(
                          TextSpan(
                            text: 'Already have an account? ',
                            style: TextStyle(
                                fontSize: 13.sp, color: AppColors.muted),
                            children: [
                              TextSpan(
                                text: 'Sign in',
                                style: TextStyle(
                                    fontSize: 13.sp,
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w700),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: 16.h),
                    Center(
                      child: Text.rich(
                        TextSpan(
                          text: 'By creating an account you agree to our ',
                          style: TextStyle(
                              fontSize: 11.5.sp, color: AppColors.muted),
                          children: [
                            TextSpan(
                                text: 'Terms',
                                style: TextStyle(
                                    fontSize: 11.5.sp,
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w600)),
                            const TextSpan(text: ' and '),
                            TextSpan(
                                text: 'Privacy Policy',
                                style: TextStyle(
                                    fontSize: 11.5.sp,
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w600)),
                            const TextSpan(
                                text: '. MedAI offers guidance, not a diagnosis.'),
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
        if (isLoading)
          const _LoadingOverlay(),
      ],
    );
  }
}

class _LoadingOverlay extends StatelessWidget {
  const _LoadingOverlay();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withValues(alpha: .5),
      child: Center(
        child: MCard(
          padding: EdgeInsets.all(24.r),
          color: Colors.white,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: AppColors.primary),
              SizedBox(height: 16.h),
              Text(
                'Connecting...',
                style: GoogleFonts.sora(
                  fontSize: 15.sp,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
              SizedBox(height: 4.h),
              Text(
                'Please wait a moment',
                style: TextStyle(
                  fontSize: 12.5.sp,
                  color: AppColors.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
