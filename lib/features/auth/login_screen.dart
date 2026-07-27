import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/shared_widgets.dart';
import '../../providers/auth_provider.dart';
import 'otp_screen.dart';

/// Login with built-in marketing: rotating value-prop hero, trust strip,
/// then US-phone sign-in. Everything is static content — zero running cost.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phone = TextEditingController();
  final _page = PageController();
  int _slide = 0;
  Timer? _auto;

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
      _page.animateToPage(next,
          duration: const Duration(milliseconds: 450),
          curve: Curves.easeOutCubic);
    });
  }

  @override
  void dispose() {
    _auto?.cancel();
    _phone.dispose();
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
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
                  const Spacer(),
                  const MChip('US · English',
                      background: AppColors.soft,
                      foreground: AppColors.onSoft),
                ],
              ),
              const SizedBox(height: 26),
              Text('Your health,\nunderstood.',
                  style: GoogleFonts.sora(
                      fontSize: 32,
                      fontWeight: FontWeight.w700,
                      height: 1.15)),
              const SizedBox(height: 8),
              const Text(
                'AI guidance, nearby care, and emergency help — in one app.',
                style: TextStyle(fontSize: 14.5, color: AppColors.muted),
              ),
              const SizedBox(height: 22),
              // Rotating value-prop hero.
              SizedBox(
                height: 148,
                child: PageView.builder(
                  controller: _page,
                  itemCount: _slides.length,
                  onPageChanged: (i) => setState(() => _slide = i),
                  itemBuilder: (_, i) {
                    final s = _slides[i];
                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      padding: const EdgeInsets.all(18),
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
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: .18),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Icon(s.$1, color: Colors.white, size: 28),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(s.$2,
                                    style: GoogleFonts.sora(
                                        fontSize: 16.5,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white)),
                                const SizedBox(height: 5),
                                Text(s.$3,
                                    style: TextStyle(
                                        fontSize: 12.5,
                                        height: 1.35,
                                        color: Colors.white
                                            .withValues(alpha: .88))),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < _slides.length; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: i == _slide ? 22 : 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: i == _slide
                            ? AppColors.primary
                            : AppColors.line,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 18),
              // Trust strip — static social proof, costs nothing.
              MCard(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
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
              const SizedBox(height: 22),
              const Text('Sign in with your phone',
                  style:
                      TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              TextField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[\d\s()\-]')),
                  LengthLimitingTextInputFormatter(14),
                ],
                decoration: const InputDecoration(
                  hintText: '(555) 000-0000',
                  prefixIcon: Icon(Icons.phone_iphone_rounded,
                      color: AppColors.muted),
                  prefixText: '+1  ',
                  prefixStyle: TextStyle(
                      color: AppColors.ink,
                      fontSize: 15,
                      fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 14),
              PrimaryButton(
                label: 'Continue',
                icon: Icons.arrow_forward_rounded,
                onPressed: () {
                  final digits =
                      _phone.text.replaceAll(RegExp(r'\D'), '');
                  if (digits.length < 10) {
                    showToast(context,
                        'Enter a valid 10-digit US phone number',
                        color: AppColors.danger);
                    return;
                  }
                  context.read<AuthProvider>().setPhone('+1 ${_phone.text}');
                  Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const OtpScreen()));
                },
              ),
              const SizedBox(height: 16),
              Center(
                child: Text.rich(
                  TextSpan(
                    text: 'By continuing you agree to our ',
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
                          text:
                              '. MedAI offers guidance, not a diagnosis.'),
                    ],
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
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
        Text(value,
            style: GoogleFonts.sora(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.primary)),
        const SizedBox(height: 2),
        Text(label,
            style: const TextStyle(fontSize: 11, color: AppColors.muted)),
      ],
    );
  }
}

class _StatDivider extends StatelessWidget {
  const _StatDivider();

  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 28, color: AppColors.line);
}
