import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import '../../core/theme/app_colors.dart';

class SosOverlayButton extends StatefulWidget {
  const SosOverlayButton({super.key});

  @override
  State<SosOverlayButton> createState() => _SosOverlayButtonState();
}

class _SosOverlayButtonState extends State<SosOverlayButton> {
  bool _isHolding = false;
  double _progress = 0.0;
  Timer? _timer;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Center(
        child: GestureDetector(
          onTapDown: (_) {
            setState(() => _isHolding = true);
            _startTimer();
          },
          onTapUp: (_) => _resetTimer(),
          onTapCancel: () => _resetTimer(),
          child: TweenAnimationBuilder<double>(
            duration: const Duration(milliseconds: 200),
            tween: Tween(begin: 0.5, end: _isHolding ? 1.0 : 0.5),
            builder: (context, opacity, child) {
              return Opacity(
                opacity: opacity,
                child: AnimatedScale(
                  duration: const Duration(milliseconds: 200),
                  scale: _isHolding ? 1.15 : 1.0, 
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Progress Ring
                      SizedBox(
                        width: 52,
                        height: 52,
                        child: CircularProgressIndicator(
                          value: _progress,
                          strokeWidth: 4.0,
                          backgroundColor: AppColors.danger.withOpacity(0.15),
                          valueColor: const AlwaysStoppedAnimation(AppColors.danger),
                        ),
                      ),
                      // The Button itself (Professional size 44x44)
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: AppColors.danger,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.danger.withOpacity(0.4),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.sos_rounded,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  void _startTimer() {
    _timer?.cancel();
    _progress = 0.0;
    
    // Tactile feedback on start
    HapticFeedback.mediumImpact();
    
    const duration = Duration(milliseconds: 40);
    _timer = Timer.periodic(duration, (t) {
      setState(() {
        _progress += 0.02; // 2 seconds total
        if (_progress >= 1.0) {
          _progress = 1.0;
          t.cancel();
          _triggerSos();
        }
      });
    });
  }

  void _resetTimer() {
    _timer?.cancel();
    setState(() {
      _isHolding = false;
      _progress = 0.0;
    });
  }

  void _triggerSos() async {
    // Strong vibration to confirm
    HapticFeedback.vibrate();
    
    // Send signal to main app
    await FlutterOverlayWindow.shareData("trigger_sos");

    _resetTimer();
  }
}
