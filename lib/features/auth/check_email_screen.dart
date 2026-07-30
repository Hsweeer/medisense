import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/shared_widgets.dart';
import '../../providers/password_reset_provider.dart';
import 'login_screen.dart';

/// Shown right after a reset link is emailed. No code to type here — the
/// user finishes the reset by tapping the link Firebase sent them.
class CheckEmailScreen extends StatefulWidget {
  const CheckEmailScreen({super.key, required this.email});

  final String email;

  @override
  State<CheckEmailScreen> createState() => _CheckEmailScreenState();
}

class _CheckEmailScreenState extends State<CheckEmailScreen> {
  bool _resending = false;
  Timer? _cooldownTimer;
  int _cooldown = 30;

  @override
  void initState() {
    super.initState();
    _startCooldown();
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    super.dispose();
  }

  void _startCooldown() {
    _cooldown = 30;
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _cooldown--);
      if (_cooldown <= 0) t.cancel();
    });
  }

  Future<void> _resend() async {
    setState(() => _resending = true);
    try {
      await context.read<PasswordResetProvider>().sendResetLink(widget.email);
      if (!mounted) return;
      showToast(context, 'Link re-sent to ${widget.email}',
          color: AppColors.primary);
      _startCooldown();
    } catch (error) {
      if (!mounted) return;
      showToast(context, error.toString(), color: AppColors.danger);
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: AppColors.soft,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: const Icon(Icons.mark_email_read_rounded,
                    color: AppColors.primary, size: 34),
              ),
              const SizedBox(height: 24),
              Text('Check your email',
                  style: GoogleFonts.sora(
                      fontSize: 28, fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              Text.rich(
                TextSpan(
                  text: 'If an account exists for ',
                  style: const TextStyle(
                      fontSize: 14.5, color: AppColors.muted, height: 1.5),
                  children: [
                    TextSpan(
                      text: widget.email,
                      style: const TextStyle(
                          color: AppColors.ink, fontWeight: FontWeight.w700),
                    ),
                    const TextSpan(
                        text: ', we\'ve sent a link to reset the password. '
                            'Open it on this device to set a new one.'),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              MCard(
                color: AppColors.paper,
                border: Border.all(color: AppColors.line),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline_rounded,
                        color: AppColors.muted, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Don\'t see it? Check spam/junk — it can take a '
                        'minute or two to arrive.',
                        style: TextStyle(
                            fontSize: 12.5,
                            color: AppColors.muted.withValues(alpha: .95),
                            height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Center(
                child: _cooldown > 0
                    ? Text('Resend link in ${_cooldown}s',
                        style: const TextStyle(
                            fontSize: 13, color: AppColors.muted))
                    : GestureDetector(
                        onTap: _resending ? null : _resend,
                        child: Text(
                          _resending ? 'Sending…' : 'Resend link',
                          style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.primary,
                              fontWeight: FontWeight.w700),
                        ),
                      ),
              ),
              const SizedBox(height: 32),
              PrimaryButton(
                label: 'Back to sign in',
                icon: Icons.arrow_back_rounded,
                onPressed: () => Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                    (_) => false),
              ),
            ],
          ),
        ),
      ),
    );
  }
}