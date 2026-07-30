import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/shared_widgets.dart';
import '../../providers/password_reset_provider.dart';
import 'check_email_screen.dart';

/// Step 1 of password reset — collect the email and request a 6-digit
/// code. Always proceeds to the OTP screen on success, even if no account
/// exists for that email (the backend intentionally doesn't reveal that,
/// so this screen shouldn't either).
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _email = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    final email = _email.text.trim();
    if (!email.contains('@') || !email.contains('.')) {
      showToast(context, 'Enter a valid email address',
          color: AppColors.danger);
      return;
    }

    setState(() => _submitting = true);
    try {
      await context.read<PasswordResetProvider>().sendResetLink(email);
      if (!mounted) return;
      Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => CheckEmailScreen(email: email)));
    } catch (error) {
      if (!mounted) return;
      showToast(context, error.toString(), color: AppColors.danger);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        appBar: AppBar(
          leading: BackButton(
            onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          ),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                        colors: AppColors.gradient,
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                          color: AppColors.primary.withValues(alpha: .3),
                          blurRadius: 16,
                          offset: const Offset(0, 6)),
                    ],
                  ),
                  child: const Icon(Icons.lock_reset_rounded,
                      color: Colors.white, size: 32),
                ),
                const SizedBox(height: 24),
                Text('Forgot your\npassword?',
                    style: GoogleFonts.sora(
                        fontSize: 30,
                        fontWeight: FontWeight.w700,
                        height: 1.15)),
                const SizedBox(height: 8),
                const Text(
                  'Enter the email on your account. We\'ll send you a '
                  'secure link to reset your password.',
                  style: TextStyle(
                      fontSize: 14.5, color: AppColors.muted, height: 1.4),
                ),
                const SizedBox(height: 28),
                const Text('Email',
                    style:
                        TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autofocus: true,
                  onSubmitted: (_) => _submitting ? null : _sendCode(),
                  decoration: const InputDecoration(
                    hintText: 'you@example.com',
                    prefixIcon: Icon(Icons.mail_outline_rounded,
                        color: AppColors.muted),
                  ),
                ),
                const SizedBox(height: 24),
                PrimaryButton(
                  label: _submitting ? 'Sending link…' : 'Send reset link',
                  icon: Icons.arrow_forward_rounded,
                  onPressed: _submitting ? null : _sendCode,
                ),
                const SizedBox(height: 16),
                Center(
                  child: GestureDetector(
                    onTap: _submitting
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: const Text('Back to sign in',
                        style: TextStyle(
                            fontSize: 13,
                            color: AppColors.primary,
                            fontWeight: FontWeight.w700)),
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