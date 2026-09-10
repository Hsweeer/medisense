// PATH: lib/features/auth/login_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/shared_widgets.dart';
import '../../providers/auth_provider.dart';
import 'forgot_password_screen.dart';
import 'signup_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
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

    try {
      await context.read<AuthProvider>().signIn(email, password);
    } catch (error) {
      if (!mounted) return;
      showToast(context, error.toString(), color: AppColors.danger);
    }
  }

  Future<void> _continueWithGoogle() async {
    try {
      await context.read<AuthProvider>().signInWithGoogle();
    } catch (error) {
      if (!mounted) return;
      showToast(context, error.toString(), color: AppColors.danger);
    }
  }

  Future<void> _continueWithApple() async {
    try {
      await context.read<AuthProvider>().signInWithApple();
    } catch (error) {
      if (!mounted) return;
      showToast(context, error.toString(), color: AppColors.danger);
    }
  }

  void _continueAsGuest() {
    context.read<AuthProvider>().continueAsGuest();
  }

  /// Simple language picker sheet. The app currently only ships English
  /// copy, so this doesn't retranslate the UI yet — it just lets the
  /// person record their preference and confirms the choice, the same
  /// way the original "US · English" chip worked before this redesign.
  void _showLanguagePicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => _LanguagePickerSheet(
        onSelected: (label) {
          Navigator.of(sheetContext).pop();
          showToast(context, 'Language set to $label');
        },
      ),
    );
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
            // Soft teal wash behind everything — matches the ambient
            // gradient in the reference design. The decorative
            // heartbeat/shield/dot artwork that used to sit on top of
            // this has been removed; only the color wash itself remains.
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
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Brand block — sits directly on the gradient
                      // background, outside the card.
                      Align(
                        alignment: Alignment.centerRight,
                        child: _LanguageChip(
                          onTap: () => _showLanguagePicker(context),
                        ),
                      ),
                      SizedBox(height: 24.h),
                      Center(child: LogoMark(size: 58.r)),
                      SizedBox(height: 8.h),
                      Center(
                        child: RichText(
                          text: TextSpan(
                            style: GoogleFonts.sora(
                              fontSize: 22.sp,
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
                      SizedBox(height: 3.h),
                      Center(
                        child: Text(
                          'Your Health. Our Priority.',
                          style: TextStyle(
                            fontSize: 11.5.sp,
                            color: AppColors.muted,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      SizedBox(height: 12.h),
                      // Floating white card — sign-in form only.
                      Container(
                        width: double.infinity,
                        padding: EdgeInsets.fromLTRB(
                          20.w,
                          18.h,
                          20.w,
                          16.h,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24.r),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withValues(
                                alpha: .10,
                              ),
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
                                'Welcome back!',
                                style: GoogleFonts.sora(
                                  fontSize: 18.sp,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.ink,
                                ),
                              ),
                            ),
                            SizedBox(height: 3.h),
                            Center(
                              child: Text(
                                'Sign in to continue to your account',
                                style: TextStyle(
                                  fontSize: 12.sp,
                                  color: AppColors.muted,
                                ),
                              ),
                            ),
                            SizedBox(height: 14.h),
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
                            SizedBox(height: 4.h),
                            Align(
                              alignment: Alignment.centerRight,
                              child: GestureDetector(
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        const ForgotPasswordScreen(),
                                  ),
                                ),
                                child: Text(
                                  'Forgot password?',
                                  style: TextStyle(
                                    fontSize: 12.sp,
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(height: 4.h),
                            PrimaryButton(
                              label: 'Sign in',
                              icon: Icons.arrow_forward_rounded,
                              onPressed: _continue,
                            ),
                            const TextDivider(text: 'OR'),
                            SocialButton(
                              label: 'Continue with Google',
                              // Real vector Google brand icon instead of a
                              // network-fetched image, which was slow and
                              // fell back to a plain "G" whenever offline
                              // or the URL failed to load.
                              iconWidget: const FaIcon(
                                FontAwesomeIcons.google,
                                color: Color(0xFF4285F4),
                                size: 18,
                              ),
                              onPressed: _continueWithGoogle,
                            ),
                            SizedBox(height: 8.h),
                            SocialButton(
                              label: 'Continue with Apple',
                              iconWidget: const FaIcon(
                                FontAwesomeIcons.apple,
                                color: Colors.black,
                                size: 20,
                              ),
                              onPressed: _continueWithApple,
                            ),
                            SizedBox(height: 10.h),
                            Center(
                              child: SizedBox(
                                width: 200.w,
                                child: SecondaryButton(
                                  label: 'Continue as Guest',
                                  icon: Icons.visibility_outlined,
                                  onPressed: _continueAsGuest,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: 12.h),
                      // Sign-up link + footer — back outside the card,
                      // directly on the gradient background.
                      Center(
                        child: GestureDetector(
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const SignupScreen(),
                            ),
                          ),
                          child: Text.rich(
                            TextSpan(
                              text: "New here? ",
                              style: TextStyle(
                                fontSize: 12.5.sp,
                                color: AppColors.muted,
                              ),
                              children: [
                                TextSpan(
                                  text: 'Create an account',
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
                      SizedBox(height: 10.h),
                      Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.shield_outlined,
                              size: 12.sp,
                              color: AppColors.primary,
                            ),
                            SizedBox(width: 5.w),
                            Flexible(
                              child: Text.rich(
                                TextSpan(
                                  text: 'By continuing you agree to our ',
                                  style: TextStyle(
                                    fontSize: 10.sp,
                                    color: AppColors.muted,
                                  ),
                                  children: [
                                    TextSpan(
                                      text: 'Terms',
                                      style: TextStyle(
                                        fontSize: 10.sp,
                                        color: AppColors.primary,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const TextSpan(text: ' and '),
                                    TextSpan(
                                      text: 'Privacy Policy',
                                      style: TextStyle(
                                        fontSize: 10.sp,
                                        color: AppColors.primary,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const TextSpan(text: '.'),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: 2.h),
                      Center(
                        child: Text(
                          'MediAI offers guidance, not a diagnosis.',
                          style: TextStyle(
                            fontSize: 9.5.sp,
                            color: AppColors.muted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        if (isLoading) const AppLoadingOverlay(),
      ],
    );
  }
}

/// Small pill in the top-right corner showing the current language/region
/// — matches the "US · English" chip from the original brand row, now
/// tappable to open a picker instead of sitting inline next to the logo.
class _LanguageChip extends StatelessWidget {
  const _LanguageChip({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MChip(
      'US · English',
      background: AppColors.soft,
      foreground: AppColors.onSoft,
      icon: Icons.language_rounded,
      onTap: onTap,
    );
  }
}

/// Bottom sheet listing available languages. Selecting one just records
/// the preference for now (see the note on [_showLanguagePicker]) — full
/// in-app translation isn't wired up yet.
class _LanguagePickerSheet extends StatelessWidget {
  const _LanguagePickerSheet({required this.onSelected});

  final ValueChanged<String> onSelected;

  static const _languages = [
    ('English (US)', Icons.check_circle_rounded, true),
    ('Español', Icons.circle_outlined, false),
    ('اردو (Urdu)', Icons.circle_outlined, false),
    ('العربية (Arabic)', Icons.circle_outlined, false),
  ];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        margin: EdgeInsets.all(12.r),
        padding: EdgeInsets.fromLTRB(20.w, 20.h, 20.w, 12.h),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24.r),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Choose language',
              style: GoogleFonts.sora(
                fontSize: 17.sp,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(height: 4.h),
            Text(
              'MedAI currently replies in English regardless of this '
              'setting — full translation is coming soon.',
              style: TextStyle(fontSize: 11.5.sp, color: AppColors.muted),
            ),
            SizedBox(height: 12.h),
            for (final lang in _languages)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  lang.$2,
                  color: lang.$3 ? AppColors.primary : AppColors.muted,
                  size: 22.sp,
                ),
                title: Text(
                  lang.$1,
                  style: TextStyle(
                    fontSize: 14.5.sp,
                    fontWeight: lang.$3 ? FontWeight.w700 : FontWeight.w500,
                    color: lang.$3 ? AppColors.ink : AppColors.inkSoft,
                  ),
                ),
                onTap: () => onSelected(lang.$1),
              ),
          ],
        ),
      ),
    );
  }
}