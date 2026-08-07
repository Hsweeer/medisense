import 'dart:async';
import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  // This channel communicates directly with Kotlin from the overlay
  static const _channel = MethodChannel('medisense_native_channel');

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
                  scale: 1.0, 
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
                      // The Button itself
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
    HapticFeedback.mediumImpact();
    
    const duration = Duration(milliseconds: 30);
    _timer = Timer.periodic(duration, (t) {
      setState(() {
        _progress += 0.1; // 0.3 seconds total (1.0 / 10 ticks)
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

  bool _isTriggered = false;

  void _triggerSos() async {
    if (_isTriggered) return;
    _isTriggered = true;

    HapticFeedback.vibrate();
    debugPrint('SOS_DEBUG: Triggering SOS via Native Broadcast (Approach B)');
    
    try {
      const intent = AndroidIntent(
        action: 'com.medisense.medisense_app.ACTION_SOS_TRIGGER',
        package: 'com.medisense.medisense_app', // Explicit target to bypass Android 8+ restrictions
      );
      await intent.sendBroadcast();
      debugPrint('SOS_DEBUG: Explicit broadcast intent sent successfully');
    } catch (e) {
      debugPrint('SOS_DEBUG: Broadcast failed: $e');
    }

    // Reset after delay to allow future triggers
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _isTriggered = false);
    });

    _resetTimer();
  }
}
