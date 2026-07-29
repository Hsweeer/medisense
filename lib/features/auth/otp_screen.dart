import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/shared_widgets.dart';
import '../../providers/auth_provider.dart';
import '../shell/patient_shell.dart';

/// 6-digit verification via Firebase Phone Auth.
class OtpScreen extends StatefulWidget {
  const OtpScreen({super.key});

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final _nodes = List.generate(6, (_) => FocusNode());
  final _ctrls = List.generate(6, (_) => TextEditingController());
  bool _verifying = false;

  @override
  void dispose() {
    for (final n in _nodes) {
      n.dispose();
    }
    for (final c in _ctrls) {
      c.dispose();
    }
    super.dispose();
  }

  String get _code => _ctrls.map((c) => c.text).join();

  Future<void> _verify() async {
    if (_code.length < 6) {
      showToast(context, 'Enter the 6-digit code', color: AppColors.danger);
      return;
    }
    setState(() => _verifying = true);
    final error = await context.read<AuthProvider>().verifyOtp(_code);
    if (!mounted) return;
    setState(() => _verifying = false);
    if (error != null) {
      showToast(context, error, color: AppColors.danger);
      return;
    }

    // TODO: jab profile-setup screen ban jaye, is check ko use karen:
    // final isNewUser = context.read<AuthProvider>().isNewUser;
    // Navigator.of(context).pushAndRemoveUntil(
    //     MaterialPageRoute(
    //         builder: (_) => isNewUser
    //             ? const ProfileSetupScreen()
    //             : const PatientShell()),
    //     (_) => false);

    Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const PatientShell()),
            (_) => false);
  }

  Future<void> _resend() async {
    final phone = context.read<AuthProvider>().phone;
    final error = await context.read<AuthProvider>().sendOtp(phone);
    if (!mounted) return;
    showToast(context,
        error ?? 'Code re-sent to $phone',
        color: error != null ? AppColors.danger : AppColors.primary);
  }

  @override
  Widget build(BuildContext context) {
    final phone = context.watch<AuthProvider>().phone;
    return Scaffold(
      appBar: AppBar(title: const Text('Verify your number')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('We texted a 6-digit code to\n$phone',
                style: const TextStyle(
                    fontSize: 15, height: 1.5, color: AppColors.inkSoft)),
            const SizedBox(height: 28),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (var i = 0; i < 6; i++)
                  SizedBox(
                    width: 46,
                    child: TextField(
                      controller: _ctrls[i],
                      focusNode: _nodes[i],
                      textAlign: TextAlign.center,
                      keyboardType: TextInputType.number,
                      maxLength: 1,
                      style: const TextStyle(
                          fontSize: 22, fontWeight: FontWeight.w700),
                      decoration:
                      const InputDecoration(counterText: ''),
                      onChanged: (v) {
                        if (v.isNotEmpty && i < 5) {
                          _nodes[i + 1].requestFocus();
                        }
                        if (v.isEmpty && i > 0) {
                          _nodes[i - 1].requestFocus();
                        }
                        if (_code.length == 6) _verify();
                      },
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            Center(
              child: TextButton(
                onPressed: _resend,
                child: const Text('Resend code',
                    style: TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w700)),
              ),
            ),
            const Spacer(),
            PrimaryButton(
              label: _verifying ? 'Verifying…' : 'Verify & continue',
              onPressed: _verifying ? null : _verify,
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}