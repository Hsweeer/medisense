import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/shared_widgets.dart';
import '../../providers/auth_provider.dart';
import '../shell/patient_shell.dart';

/// 4-digit verification. Any code works in this frontend build.
class OtpScreen extends StatefulWidget {
  const OtpScreen({super.key});

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final _nodes = List.generate(4, (_) => FocusNode());
  final _ctrls = List.generate(4, (_) => TextEditingController());

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

  void _verify() {
    if (_code.length < 4) {
      showToast(context, 'Enter the 4-digit code', color: AppColors.danger);
      return;
    }
    context.read<AuthProvider>().verify();
    Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const PatientShell()),
        (_) => false);
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
            Text('We texted a 4-digit code to\n$phone',
                style: const TextStyle(
                    fontSize: 15, height: 1.5, color: AppColors.inkSoft)),
            const SizedBox(height: 28),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (var i = 0; i < 4; i++)
                  SizedBox(
                    width: 68,
                    child: TextField(
                      controller: _ctrls[i],
                      focusNode: _nodes[i],
                      textAlign: TextAlign.center,
                      keyboardType: TextInputType.number,
                      maxLength: 1,
                      style: const TextStyle(
                          fontSize: 24, fontWeight: FontWeight.w700),
                      decoration:
                          const InputDecoration(counterText: ''),
                      onChanged: (v) {
                        if (v.isNotEmpty && i < 3) {
                          _nodes[i + 1].requestFocus();
                        }
                        if (v.isEmpty && i > 0) {
                          _nodes[i - 1].requestFocus();
                        }
                        if (_code.length == 4) _verify();
                      },
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            Center(
              child: TextButton(
                onPressed: () =>
                    showToast(context, 'Code re-sent to $phone'),
                child: const Text('Resend code',
                    style: TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w700)),
              ),
            ),
            const Spacer(),
            PrimaryButton(label: 'Verify & continue', onPressed: _verify),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
