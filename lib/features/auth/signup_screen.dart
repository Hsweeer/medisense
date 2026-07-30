import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/shared_widgets.dart';
import '../../providers/auth_provider.dart';
import '../../providers/profile_provider.dart';
import '../shell/patient_shell.dart';

/// Dedicated account-creation screen. On success this takes the new user
/// straight to [PatientShell] (Home) — no separate "verify" step.
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

  bool _submitting = false;
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
      showToast(context, 'Enter a valid email address',
          color: AppColors.danger);
      return;
    }
    if (password.length < 6) {
      showToast(context, 'Password must be at least 6 characters',
          color: AppColors.danger);
      return;
    }
    if (password != confirm) {
      showToast(context, 'Passwords don\'t match', color: AppColors.danger);
      return;
    }

    setState(() => _submitting = true);
    try {
      await context.read<AuthProvider>().signUp(name, email, password);

      if (!mounted) return;

      context.read<ProfileProvider>().refreshForCurrentUser();

      // New user, freshly registered — go straight to Home.
      Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const PatientShell()),
          (_) => false);
    } catch (error) {
      if (!mounted) return;
      showToast(context, error.toString(), color: AppColors.danger);
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
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
                Row(
                  children: [
                    const LogoMark(size: 42),
                    const SizedBox(width: 10),
                    Text('MediSense',
                        style: GoogleFonts.sora(
                            fontSize: 20, fontWeight: FontWeight.w700)),
                  ],
                ),
                const SizedBox(height: 26),
                Text('Create your\naccount',
                    style: GoogleFonts.sora(
                        fontSize: 32,
                        fontWeight: FontWeight.w700,
                        height: 1.15)),
                const SizedBox(height: 8),
                const Text(
                  'Takes less than a minute. You\'ll land straight on your '
                  'home dashboard once you\'re done.',
                  style: TextStyle(fontSize: 14.5, color: AppColors.muted),
                ),
                const SizedBox(height: 26),
                const Text('Full name',
                    style:
                        TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                TextField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    hintText: 'Jordan Blake',
                    prefixIcon: Icon(Icons.person_outline_rounded,
                        color: AppColors.muted),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Email',
                    style:
                        TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    hintText: 'you@example.com',
                    prefixIcon: Icon(Icons.mail_outline_rounded,
                        color: AppColors.muted),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Password',
                    style:
                        TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                TextField(
                  controller: _password,
                  obscureText: _obscure,
                  decoration: InputDecoration(
                    hintText: 'At least 6 characters',
                    prefixIcon: const Icon(Icons.lock_outline_rounded,
                        color: AppColors.muted),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscure
                            ? Icons.visibility_off_rounded
                            : Icons.visibility_rounded,
                        color: AppColors.muted,
                      ),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Confirm password',
                    style:
                        TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                TextField(
                  controller: _confirm,
                  obscureText: _obscureConfirm,
                  decoration: InputDecoration(
                    hintText: 'Re-enter your password',
                    prefixIcon: const Icon(Icons.lock_outline_rounded,
                        color: AppColors.muted),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureConfirm
                            ? Icons.visibility_off_rounded
                            : Icons.visibility_rounded,
                        color: AppColors.muted,
                      ),
                      onPressed: () =>
                          setState(() => _obscureConfirm = !_obscureConfirm),
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                PrimaryButton(
                  label: _submitting ? 'Creating account…' : 'Create account',
                  icon: Icons.arrow_forward_rounded,
                  onPressed: _submitting ? null : _createAccount,
                ),
                const SizedBox(height: 16),
                Center(
                  child: GestureDetector(
                    onTap: _submitting
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: Text.rich(
                      TextSpan(
                        text: 'Already have an account? ',
                        style: const TextStyle(
                            fontSize: 13, color: AppColors.muted),
                        children: [
                          TextSpan(
                            text: 'Sign in',
                            style: TextStyle(
                                fontSize: 13,
                                color: AppColors.primary,
                                fontWeight: FontWeight.w700),
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
                      text: 'By creating an account you agree to our ',
                      style: const TextStyle(
                          fontSize: 11.5, color: AppColors.muted),
                      children: [
                        TextSpan(
                            text: 'Terms',
                            style: TextStyle(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w600)),
                        const TextSpan(text: ' and '),
                        TextSpan(
                            text: 'Privacy Policy',
                            style: TextStyle(
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
    );
  }
}